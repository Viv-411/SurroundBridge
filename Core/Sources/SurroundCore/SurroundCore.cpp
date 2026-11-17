//
//  SurroundCore.cpp
//  SurroundBridge
//
//  See SurroundCore.h for the overview and the threading rules.
//

#include "SurroundCore.h"

#include <Accelerate/Accelerate.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstring>
#include <mutex>

namespace {

constexpr int NC = SB_NUM_CHANNELS;
constexpr int NB = SB_NUM_EQ_BANDS;
/// Each speaker runs its own bands followed by the master bands, as one chain of filters.
constexpr int kEqSections = 2 * NB;
/// Largest block processed in one go; bigger requests are split up. (AC-3 packets are 1536 frames.)
constexpr uint32_t kMaxBlock = 4096;
/// Length of each delay line. A power of two so wrapping around is a cheap bit-mask. Covers 200 ms up to 96 kHz.
constexpr uint32_t kDelayLen = 32768;
constexpr uint32_t kDelayMask = kDelayLen - 1;
/// How far the limiter "looks into the future" (in samples) so it can turn down before a peak arrives.
constexpr uint32_t kLookahead = 64;
constexpr int kBassSections = 2; // two 2nd-order Butterworth filters in a row = 4th-order Linkwitz-Riley

inline float DbToLinear(float db) { return std::pow(10.0f, db / 20.0f); }
inline float Clamp(float v, float lo, float hi) { return std::min(std::max(v, lo), hi); }

/// Everything the audio thread needs, pre-computed by the UI thread (so the audio thread does no heavy maths).
struct RTParams
{
  double sampleRate;
  bool bypass;
  float route[NC][NC];
  float channelGain[NC]; ///< linear, already includes master volume, mute and solo
  float toneGain[NC];    ///< like channelGain but ignoring mute/solo (a test tone should always be audible)
  uint32_t delaySamples[NC];
  bool eqActive[NC];
  double eqCoeffs[NC][kEqSections * 5];

  bool bassEnabled;
  bool bassFrom[NC];
  float bassGain;
  double lowpass[kBassSections * 5];
  double highpass[kBassSections * 5];

  bool limiterEnabled;
  float limiterCeiling;
  float limiterReleaseCoeff;

  int32_t toneChannel;
  int32_t toneType;
  float toneFreq;
  float toneLevel;
};

/// Lock-free hand-over of the newest value from one writer thread to one reader thread.
/// Three slots: one the writer fills, one the reader uses, one "in the middle" that they swap with atomically.
template <typename T>
class TripleBuffer
{
public:
  /// Writer thread.
  void Write(const T &value)
  {
    _slots[_writeIndex] = value;
    const uint32_t old = _middle.exchange(_writeIndex | kDirty, std::memory_order_acq_rel);
    _writeIndex = old & kIndexMask;
  }

  /// Reader thread. @return the newest value if one arrived since the last call, otherwise nullptr.
  const T *Read()
  {
    if (!(_middle.load(std::memory_order_acquire) & kDirty))
      return nullptr;
    const uint32_t old = _middle.exchange(_readIndex, std::memory_order_acq_rel);
    _readIndex = old & kIndexMask;
    return &_slots[_readIndex];
  }

private:
  static constexpr uint32_t kDirty = 4;
  static constexpr uint32_t kIndexMask = 3;
  T _slots[3] = {};
  std::atomic<uint32_t> _middle{1};
  uint32_t _writeIndex = 0;
  uint32_t _readIndex = 2;
};

void DesignButterworth(bool highpass, double freqHz, double sampleRate, double coeffs[5])
{
  SBEQBand band = {};
  band.type = highpass ? SB_FILTER_HIGH_PASS : SB_FILTER_LOW_PASS;
  band.enabled = true;
  band.freqHz = static_cast<float>(freqHz);
  band.q = 0.70710678f;
  sb_biquad_design(&band, sampleRate, coeffs);
}

RTParams DeriveRTParams(const SBParams &p, double sampleRate)
{
  RTParams rt = {};
  rt.sampleRate = sampleRate;
  rt.bypass = p.bypass;

  bool anySolo = false;
  for (int c = 0; c < NC; ++c)
    anySolo = anySolo || p.channels[c].solo;

  for (int o = 0; o < NC; ++o)
  {
    for (int i = 0; i < NC; ++i)
      rt.route[o][i] = p.routing[o][i];

    const SBChannelParams &ch = p.channels[o];
    const float gain = DbToLinear(ch.gainDb + p.masterGainDb);
    const bool silent = ch.mute || (anySolo && !ch.solo);
    rt.channelGain[o] = silent ? 0.0f : gain;
    rt.toneGain[o] = gain;

    const double delayMs = Clamp(ch.delayMs, 0.0f, static_cast<float>(SB_MAX_DELAY_MS));
    rt.delaySamples[o] = std::min(static_cast<uint32_t>(std::lround(delayMs * sampleRate / 1000.0)), kDelayLen - 1);

    rt.eqActive[o] = false;
    for (int b = 0; b < NB; ++b)
    {
      sb_biquad_design(&ch.eq[b], sampleRate, &rt.eqCoeffs[o][b * 5]);
      sb_biquad_design(&p.masterEq[b], sampleRate, &rt.eqCoeffs[o][(NB + b) * 5]);
      rt.eqActive[o] = rt.eqActive[o] || ch.eq[b].enabled || p.masterEq[b].enabled;
    }
  }

  bool anyBassSource = false;
  for (int c = 0; c < NC; ++c)
  {
    rt.bassFrom[c] = p.bassFromChannel[c] && c != SB_CH_LFE;
    anyBassSource = anyBassSource || rt.bassFrom[c];
  }
  rt.bassEnabled = p.bassEnabled && anyBassSource;
  rt.bassGain = DbToLinear(p.bassRedirectGainDb);
  const double crossover = Clamp(p.crossoverHz, 20.0f, 500.0f);
  for (int s = 0; s < kBassSections; ++s)
  {
    DesignButterworth(false, crossover, sampleRate, &rt.lowpass[s * 5]);
    DesignButterworth(true, crossover, sampleRate, &rt.highpass[s * 5]);
  }

  rt.limiterEnabled = p.limiterEnabled;
  rt.limiterCeiling = DbToLinear(Clamp(p.limiterCeilingDb, -24.0f, 0.0f));
  const double releaseSamples = std::max(1.0, Clamp(p.limiterReleaseMs, 1.0f, 2000.0f) * sampleRate / 1000.0);
  rt.limiterReleaseCoeff = static_cast<float>(1.0 - std::exp(-1.0 / releaseSamples));

  rt.toneChannel = (p.toneChannel >= 0 && p.toneChannel < NC) ? p.toneChannel : -1;
  rt.toneType = p.toneType;
  rt.toneFreq = Clamp(p.toneFreqHz, 20.0f, 20000.0f);
  rt.toneLevel = DbToLinear(Clamp(p.toneLevelDb, -60.0f, 0.0f));
  return rt;
}

} // namespace

struct SBEngine
{
  explicit SBEngine(double sampleRate);
  ~SBEngine();

  void SetParams(const SBParams &params);
  void SetSampleRate(double sampleRate);
  void Process(const float *input, float *output, uint32_t numFrames);

  // ---- shared between threads (atomics only) ----
  std::atomic<float> inputPeak[NC];
  std::atomic<float> outputPeak[NC];
  std::atomic<float> limiterMinGain{1.0f};
  std::atomic<double> sampleRateForReaders;

private:
  void ApplyNewParams(const RTParams &newParams);
  void ProcessChunk(const float *input, float *output, uint32_t n);
  void GenerateTone(float *dest, uint32_t n);
  void RunLimiter(uint32_t n);

  // ---- UI side (protected by _writerMutex, never touched by the audio thread) ----
  std::mutex _writerMutex;
  SBParams _params;
  double _sampleRate;

  TripleBuffer<RTParams> _exchange;

  // ---- audio thread only ----
  RTParams _rt;
  float _currentRoute[NC][NC];
  float _currentGain[NC];

  vDSP_biquad_Setup _eqSetup[NC];
  float _eqState[NC][2 * kEqSections + 2];
  vDSP_biquad_Setup _highpassSetup[NC];
  float _highpassState[NC][2 * kBassSections + 2];
  vDSP_biquad_Setup _lowpassSetup;
  float _lowpassState[2 * kBassSections + 2];

  float _delayLine[NC][kDelayLen];
  uint32_t _delayPos = 0;

  float _lookahead[NC][kLookahead];
  uint32_t _lookaheadPos = 0;
  float _limiterEnvelope = 1.0f;
  float _limiterSmoothed = 1.0f;
  uint32_t _limiterHold = 0;
  float _limiterAttackCoeff;

  double _tonePhase = 0.0;
  uint32_t _noiseState = 0x12345678u;
  float _pink[3] = {0, 0, 0};

  float _in[NC][kMaxBlock];
  float _out[NC][kMaxBlock];
  float _bass[kMaxBlock];
  float _scratch[kMaxBlock];
};

SBEngine::SBEngine(double sampleRate) : _sampleRate(sampleRate)
{
  sb_params_init_default(&_params);
  _rt = DeriveRTParams(_params, _sampleRate);
  sampleRateForReaders.store(_sampleRate);

  for (int c = 0; c < NC; ++c)
  {
    inputPeak[c].store(0.0f);
    outputPeak[c].store(0.0f);
    _eqSetup[c] = vDSP_biquad_CreateSetup(_rt.eqCoeffs[c], kEqSections);
    _highpassSetup[c] = vDSP_biquad_CreateSetup(_rt.highpass, kBassSections);
    _currentGain[c] = _rt.channelGain[c];
    for (int i = 0; i < NC; ++i)
      _currentRoute[c][i] = _rt.route[c][i];
  }
  _lowpassSetup = vDSP_biquad_CreateSetup(_rt.lowpass, kBassSections);

  std::memset(_eqState, 0, sizeof _eqState);
  std::memset(_highpassState, 0, sizeof _highpassState);
  std::memset(_lowpassState, 0, sizeof _lowpassState);
  std::memset(_delayLine, 0, sizeof _delayLine);
  std::memset(_lookahead, 0, sizeof _lookahead);

  // the gain smoother settles (to within 1%) in the time the look-ahead gives us
  _limiterAttackCoeff = 1.0f - std::exp(-5.0f / static_cast<float>(kLookahead));
}

SBEngine::~SBEngine()
{
  for (int c = 0; c < NC; ++c)
  {
    vDSP_biquad_DestroySetup(_eqSetup[c]);
    vDSP_biquad_DestroySetup(_highpassSetup[c]);
  }
  vDSP_biquad_DestroySetup(_lowpassSetup);
}

void SBEngine::SetParams(const SBParams &params)
{
  std::lock_guard<std::mutex> lock(_writerMutex);
  _params = params;
  _exchange.Write(DeriveRTParams(_params, _sampleRate));
}

void SBEngine::SetSampleRate(double sampleRate)
{
  std::lock_guard<std::mutex> lock(_writerMutex);
  if (sampleRate <= 0.0 || sampleRate == _sampleRate)
    return;
  _sampleRate = sampleRate;
  sampleRateForReaders.store(sampleRate);
  _exchange.Write(DeriveRTParams(_params, _sampleRate));
}

// ---------------------------------------------------------------------------------------------
// Everything below runs on the real-time audio thread: no allocation, no locks, no I/O.
// ---------------------------------------------------------------------------------------------

void SBEngine::ApplyNewParams(const RTParams &newParams)
{
  const bool bassWasEnabled = _rt.bassEnabled;
  bool eqWasActive[NC];
  for (int c = 0; c < NC; ++c)
    eqWasActive[c] = _rt.eqActive[c];

  _rt = newParams;

  for (int c = 0; c < NC; ++c)
  {
    vDSP_biquad_SetCoefficientsDouble(_eqSetup[c], _rt.eqCoeffs[c], 0, kEqSections);
    vDSP_biquad_SetCoefficientsDouble(_highpassSetup[c], _rt.highpass, 0, kBassSections);
    if (_rt.eqActive[c] && !eqWasActive[c])
      std::memset(_eqState[c], 0, sizeof _eqState[c]); // start a freshly enabled filter from silence
  }
  vDSP_biquad_SetCoefficientsDouble(_lowpassSetup, _rt.lowpass, 0, kBassSections);
  if (_rt.bassEnabled && !bassWasEnabled)
  {
    std::memset(_highpassState, 0, sizeof _highpassState);
    std::memset(_lowpassState, 0, sizeof _lowpassState);
  }
}

void SBEngine::Process(const float *input, float *output, uint32_t numFrames)
{
  if (const RTParams *newParams = _exchange.Read())
    ApplyNewParams(*newParams);

  while (numFrames > 0)
  {
    const uint32_t n = std::min(numFrames, kMaxBlock);
    ProcessChunk(input, output, n);
    input += n * NC;
    output += n * NC;
    numFrames -= n;
  }
}

static inline void StorePeak(std::atomic<float> &slot, const float *samples, uint32_t n)
{
  float peak = 0.0f;
  vDSP_maxmgv(samples, 1, &peak, n);
  if (peak > slot.load(std::memory_order_relaxed))
    slot.store(peak, std::memory_order_relaxed);
}

void SBEngine::GenerateTone(float *dest, uint32_t n)
{
  const bool isSub = _rt.toneChannel == SB_CH_LFE;
  if (isSub || _rt.toneType == SB_TONE_SINE)
  { // the subwoofer can't reproduce noise or mid tones, so it always gets a low hum
    const double freq = isSub ? 50.0 : _rt.toneFreq;
    const double step = 2.0 * M_PI * freq / _rt.sampleRate;
    for (uint32_t k = 0; k < n; ++k)
    {
      dest[k] = _rt.toneLevel * static_cast<float>(std::sin(_tonePhase));
      _tonePhase += step;
      if (_tonePhase > 2.0 * M_PI)
        _tonePhase -= 2.0 * M_PI;
    }
  }
  else
  { // pink noise: white noise filtered so every octave is equally loud (Paul Kellet's "economy" filter)
    for (uint32_t k = 0; k < n; ++k)
    {
      _noiseState ^= _noiseState << 13;
      _noiseState ^= _noiseState >> 17;
      _noiseState ^= _noiseState << 5;
      const float white = static_cast<float>(_noiseState) * (2.0f / 4294967295.0f) - 1.0f;
      _pink[0] = 0.99765f * _pink[0] + white * 0.0990460f;
      _pink[1] = 0.96300f * _pink[1] + white * 0.2965164f;
      _pink[2] = 0.57000f * _pink[2] + white * 1.0526913f;
      dest[k] = _rt.toneLevel * 0.25f * (_pink[0] + _pink[1] + _pink[2] + white * 0.1848f);
    }
  }
}

void SBEngine::RunLimiter(uint32_t n)
{
  const float ceiling = _rt.limiterCeiling;
  float minGain = 1.0f;
  for (uint32_t k = 0; k < n; ++k)
  {
    // loudest channel right now decides the gain for all channels (keeps the sound image stable)
    float peak = 0.0f;
    for (int c = 0; c < NC; ++c)
      peak = std::max(peak, std::fabs(_out[c][k]));
    const float target = peak > ceiling ? ceiling / peak : 1.0f;

    if (target <= _limiterEnvelope)
    { // need to turn down: do it immediately and hold until the loud sample has left the look-ahead buffer
      _limiterEnvelope = target;
      _limiterHold = kLookahead;
    }
    else if (_limiterHold > 0)
      --_limiterHold;
    else
      _limiterEnvelope += (1.0f - _limiterEnvelope) * _rt.limiterReleaseCoeff;

    // smooth the gain change so it doesn't click
    _limiterSmoothed += (_limiterEnvelope - _limiterSmoothed) * _limiterAttackCoeff;
    minGain = std::min(minGain, _limiterSmoothed);

    for (int c = 0; c < NC; ++c)
    {
      const float delayed = _lookahead[c][_lookaheadPos];
      _lookahead[c][_lookaheadPos] = _out[c][k];
      // final hard clamp: guarantees the ceiling is never exceeded, whatever happens above
      _out[c][k] = Clamp(delayed * _limiterSmoothed, -ceiling, ceiling);
    }
    _lookaheadPos = (_lookaheadPos + 1) % kLookahead;
  }
  if (minGain < limiterMinGain.load(std::memory_order_relaxed))
    limiterMinGain.store(minGain, std::memory_order_relaxed);
}

void SBEngine::ProcessChunk(const float *input, float *output, uint32_t n)
{
  // 1. split the interleaved input (L R C LFE Ls Rs L R C ...) into one buffer per channel
  for (int c = 0; c < NC; ++c)
  {
    for (uint32_t k = 0; k < n; ++k)
      _in[c][k] = input[k * NC + c];
    StorePeak(inputPeak[c], _in[c], n);
  }

  if (_rt.bypass)
  {
    if (output != input)
      std::memmove(output, input, n * NC * sizeof(float));
    for (int c = 0; c < NC; ++c)
      StorePeak(outputPeak[c], _in[c], n);
    return;
  }

  const bool toneActive = _rt.toneChannel >= 0;
  if (toneActive)
  { // test tone: silence everything, then put the tone on exactly one speaker
    for (int c = 0; c < NC; ++c)
      std::memset(_out[c], 0, n * sizeof(float));
    GenerateTone(_out[_rt.toneChannel], n);
    for (int o = 0; o < NC; ++o)
      for (int i = 0; i < NC; ++i)
        _currentRoute[o][i] = _rt.route[o][i];
  }
  else
  {
    // 2. routing matrix: every output is a weighted sum of the inputs
    for (int o = 0; o < NC; ++o)
    {
      std::memset(_out[o], 0, n * sizeof(float));
      for (int i = 0; i < NC; ++i)
      {
        const float from = _currentRoute[o][i];
        const float to = _rt.route[o][i];
        if (from == 0.0f && to == 0.0f)
          continue;
        if (from == to)
          vDSP_vsma(_in[i], 1, &to, _out[o], 1, _out[o], 1, n);
        else
        { // the gain changed: glide to the new value over this block instead of jumping (avoids clicks)
          const float step = (to - from) / static_cast<float>(n);
          float gain = from;
          for (uint32_t k = 0; k < n; ++k)
          {
            gain += step;
            _out[o][k] += _in[i][k] * gain;
          }
          _currentRoute[o][i] = to;
        }
      }
    }

    // 3. bass management: take the lows out of the chosen speakers and give them to the subwoofer
    if (_rt.bassEnabled)
    {
      std::memset(_bass, 0, n * sizeof(float));
      for (int c = 0; c < NC; ++c)
      {
        if (!_rt.bassFrom[c])
          continue;
        vDSP_vadd(_out[c], 1, _bass, 1, _bass, 1, n);
        vDSP_biquad(_highpassSetup[c], _highpassState[c], _out[c], 1, _scratch, 1, n);
        std::memcpy(_out[c], _scratch, n * sizeof(float));
      }
      vDSP_biquad(_lowpassSetup, _lowpassState, _bass, 1, _scratch, 1, n);
      vDSP_vsma(_scratch, 1, &_rt.bassGain, _out[SB_CH_LFE], 1, _out[SB_CH_LFE], 1, n);
    }
  }

  for (int c = 0; c < NC; ++c)
  {
    // 4. parametric EQ: a chain of biquad filters
    if (_rt.eqActive[c])
    {
      vDSP_biquad(_eqSetup[c], _eqState[c], _out[c], 1, _scratch, 1, n);
      std::memcpy(_out[c], _scratch, n * sizeof(float));
    }

    // 5. volume (with mute / solo / master folded in), gliding to new values
    const float from = _currentGain[c];
    const float to = toneActive ? _rt.toneGain[c] : _rt.channelGain[c];
    if (from == to)
    {
      if (to != 1.0f)
        vDSP_vsmul(_out[c], 1, &to, _out[c], 1, n);
    }
    else
    {
      const float step = (to - from) / static_cast<float>(n);
      float gain = from;
      for (uint32_t k = 0; k < n; ++k)
      {
        gain += step;
        _out[c][k] *= gain;
      }
      _currentGain[c] = to;
    }

    // 6. delay: write into a circular buffer, read from `delay` samples earlier
    const uint32_t delay = _rt.delaySamples[c];
    float *line = _delayLine[c];
    for (uint32_t k = 0; k < n; ++k)
    {
      const uint32_t pos = (_delayPos + k) & kDelayMask;
      line[pos] = _out[c][k];
      _out[c][k] = line[(pos - delay) & kDelayMask];
    }
  }
  _delayPos = (_delayPos + n) & kDelayMask;

  // 7. safety limiter
  if (_rt.limiterEnabled)
    RunLimiter(n);
  else
  {
    _limiterEnvelope = 1.0f;
    _limiterSmoothed = 1.0f;
    _limiterHold = 0;
  }

  // 8. back to interleaved
  for (int c = 0; c < NC; ++c)
  {
    StorePeak(outputPeak[c], _out[c], n);
    for (uint32_t k = 0; k < n; ++k)
      output[k * NC + c] = _out[c][k];
  }
}

// ---------------------------------------------------------------------------------------------
// C interface
// ---------------------------------------------------------------------------------------------

void sb_params_init_default(SBParams *params)
{
  static const float kBandFreqs[NB] = {60.0f, 250.0f, 1000.0f, 4000.0f, 12000.0f};
  static const int32_t kBandTypes[NB] = {SB_FILTER_LOW_SHELF, SB_FILTER_PEAK, SB_FILTER_PEAK, SB_FILTER_PEAK, SB_FILTER_HIGH_SHELF};

  std::memset(params, 0, sizeof *params);
  for (int c = 0; c < NC; ++c)
  {
    params->routing[c][c] = 1.0f;
    params->bassFromChannel[c] = c != SB_CH_LFE;
    for (int b = 0; b < NB; ++b)
    {
      SBEQBand &band = params->channels[c].eq[b];
      band.type = kBandTypes[b];
      band.enabled = false;
      band.freqHz = kBandFreqs[b];
      band.gainDb = 0.0f;
      band.q = band.type == SB_FILTER_PEAK ? 1.0f : 0.7071f;
    }
  }
  for (int b = 0; b < NB; ++b)
    params->masterEq[b] = params->channels[0].eq[b];
  params->bassEnabled = false;
  params->crossoverHz = 80.0f;
  params->bassRedirectGainDb = -10.0f;
  params->limiterEnabled = true;
  params->limiterCeilingDb = -1.0f;
  params->limiterReleaseMs = 100.0f;
  params->toneChannel = -1;
  params->toneType = SB_TONE_PINK_NOISE;
  params->toneFreqHz = 440.0f;
  params->toneLevelDb = -20.0f;
}

static inline bool ValidChannel(int32_t c) { return c >= 0 && c < NC; }

void sb_params_set_route(SBParams *params, int32_t outChannel, int32_t inChannel, float linearGain)
{
  if (ValidChannel(outChannel) && ValidChannel(inChannel))
    params->routing[outChannel][inChannel] = linearGain;
}

float sb_params_get_route(const SBParams *params, int32_t outChannel, int32_t inChannel)
{
  return (ValidChannel(outChannel) && ValidChannel(inChannel)) ? params->routing[outChannel][inChannel] : 0.0f;
}

SBChannelParams *sb_params_channel(SBParams *params, int32_t channel)
{
  return &params->channels[ValidChannel(channel) ? channel : 0];
}

SBEQBand *sb_channel_band(SBChannelParams *channel, int32_t band)
{
  return &channel->eq[(band >= 0 && band < NB) ? band : 0];
}

SBEQBand *sb_params_master_band(SBParams *params, int32_t band)
{
  return &params->masterEq[(band >= 0 && band < NB) ? band : 0];
}

void sb_params_set_bass_from(SBParams *params, int32_t channel, bool enabled)
{
  if (ValidChannel(channel))
    params->bassFromChannel[channel] = enabled;
}

SBEngine *sb_engine_create(double sampleRate) { return new SBEngine(sampleRate); }
void sb_engine_destroy(SBEngine *engine) { delete engine; }

SBEngine *sb_shared_engine(void)
{
  static SBEngine *shared = new SBEngine(48000.0);
  return shared;
}

void sb_engine_set_sample_rate(SBEngine *engine, double sampleRate) { engine->SetSampleRate(sampleRate); }
double sb_engine_sample_rate(SBEngine *engine) { return engine->sampleRateForReaders.load(); }
void sb_engine_set_params(SBEngine *engine, const SBParams *params) { engine->SetParams(*params); }

void sb_engine_process(SBEngine *engine, const float *input, float *output, uint32_t numFrames)
{
  engine->Process(input, output, numFrames);
}

float sb_engine_take_input_peak(SBEngine *engine, int32_t channel)
{
  return ValidChannel(channel) ? engine->inputPeak[channel].exchange(0.0f, std::memory_order_relaxed) : 0.0f;
}

float sb_engine_take_output_peak(SBEngine *engine, int32_t channel)
{
  return ValidChannel(channel) ? engine->outputPeak[channel].exchange(0.0f, std::memory_order_relaxed) : 0.0f;
}

float sb_engine_take_limiter_reduction_db(SBEngine *engine)
{
  const float gain = engine->limiterMinGain.exchange(1.0f, std::memory_order_relaxed);
  return gain >= 1.0f ? 0.0f : -20.0f * std::log10(std::max(gain, 1e-6f));
}

// ---- filter maths: formulas from Robert Bristow-Johnson's "Audio EQ Cookbook" ----

void sb_biquad_design(const SBEQBand *band, double sampleRate, double coeffs[5])
{
  coeffs[0] = 1.0;
  coeffs[1] = coeffs[2] = coeffs[3] = coeffs[4] = 0.0;
  if (!band->enabled || sampleRate <= 0.0)
    return;

  const double freq = std::min(std::max(static_cast<double>(band->freqHz), 10.0), 0.45 * sampleRate);
  const double q = std::min(std::max(static_cast<double>(band->q), 0.1), 20.0);
  const double A = std::pow(10.0, band->gainDb / 40.0);
  const double w0 = 2.0 * M_PI * freq / sampleRate;
  const double cosw = std::cos(w0);
  const double alpha = std::sin(w0) / (2.0 * q);
  const double sqrtA2alpha = 2.0 * std::sqrt(A) * alpha;

  double b0, b1, b2, a0, a1, a2;
  switch (band->type)
  {
    case SB_FILTER_LOW_SHELF:
      b0 = A * ((A + 1.0) - (A - 1.0) * cosw + sqrtA2alpha);
      b1 = 2.0 * A * ((A - 1.0) - (A + 1.0) * cosw);
      b2 = A * ((A + 1.0) - (A - 1.0) * cosw - sqrtA2alpha);
      a0 = (A + 1.0) + (A - 1.0) * cosw + sqrtA2alpha;
      a1 = -2.0 * ((A - 1.0) + (A + 1.0) * cosw);
      a2 = (A + 1.0) + (A - 1.0) * cosw - sqrtA2alpha;
      break;
    case SB_FILTER_HIGH_SHELF:
      b0 = A * ((A + 1.0) + (A - 1.0) * cosw + sqrtA2alpha);
      b1 = -2.0 * A * ((A - 1.0) + (A + 1.0) * cosw);
      b2 = A * ((A + 1.0) + (A - 1.0) * cosw - sqrtA2alpha);
      a0 = (A + 1.0) - (A - 1.0) * cosw + sqrtA2alpha;
      a1 = 2.0 * ((A - 1.0) - (A + 1.0) * cosw);
      a2 = (A + 1.0) - (A - 1.0) * cosw - sqrtA2alpha;
      break;
    case SB_FILTER_HIGH_PASS:
      b0 = (1.0 + cosw) / 2.0;
      b1 = -(1.0 + cosw);
      b2 = (1.0 + cosw) / 2.0;
      a0 = 1.0 + alpha;
      a1 = -2.0 * cosw;
      a2 = 1.0 - alpha;
      break;
    case SB_FILTER_LOW_PASS:
      b0 = (1.0 - cosw) / 2.0;
      b1 = 1.0 - cosw;
      b2 = (1.0 - cosw) / 2.0;
      a0 = 1.0 + alpha;
      a1 = -2.0 * cosw;
      a2 = 1.0 - alpha;
      break;
    case SB_FILTER_PEAK:
    default:
      b0 = 1.0 + alpha * A;
      b1 = -2.0 * cosw;
      b2 = 1.0 - alpha * A;
      a0 = 1.0 + alpha / A;
      a1 = -2.0 * cosw;
      a2 = 1.0 - alpha / A;
      break;
  }
  coeffs[0] = b0 / a0;
  coeffs[1] = b1 / a0;
  coeffs[2] = b2 / a0;
  coeffs[3] = a1 / a0;
  coeffs[4] = a2 / a0;
}

double sb_biquad_magnitude_db(const double coeffs[5], double freqHz, double sampleRate)
{
  // evaluate H(z) = (b0 + b1/z + b2/z^2) / (1 + a1/z + a2/z^2) on the unit circle
  const double w = 2.0 * M_PI * freqHz / sampleRate;
  const double c1 = std::cos(w), s1 = std::sin(w), c2 = std::cos(2.0 * w), s2 = std::sin(2.0 * w);
  const double numRe = coeffs[0] + coeffs[1] * c1 + coeffs[2] * c2;
  const double numIm = -(coeffs[1] * s1 + coeffs[2] * s2);
  const double denRe = 1.0 + coeffs[3] * c1 + coeffs[4] * c2;
  const double denIm = -(coeffs[3] * s1 + coeffs[4] * s2);
  const double magSquared = (numRe * numRe + numIm * numIm) / std::max(denRe * denRe + denIm * denIm, 1e-30);
  return 10.0 * std::log10(std::max(magSquared, 1e-30));
}

double sb_eq_response_db(const SBEQBand *bands, int32_t numBands, double freqHz, double sampleRate)
{
  double total = 0.0;
  for (int32_t b = 0; b < numBands; ++b)
  {
    double coeffs[5];
    sb_biquad_design(&bands[b], sampleRate, coeffs);
    total += sb_biquad_magnitude_db(coeffs, freqHz, sampleRate);
  }
  return total;
}
