//
//  SurroundCore.h
//  SurroundBridge
//
//  The audio processing stage that sits between capture and the AC-3 encoder:
//
//    6 input channels -> routing matrix -> bass management -> per-channel EQ
//      -> volume / mute / solo -> delay -> safety limiter -> 6 output channels
//
//  Plain C interface so it can be called from C++ (the audio thread), Swift (the UI) and the tests.
//
//  Threading rules:
//   - sb_engine_process() is the ONLY function meant for the real-time audio thread. It never
//     allocates memory, takes locks, or does I/O.
//   - Everything else is for normal threads (UI). Parameter changes travel to the audio thread
//     through a lock-free "triple buffer", so neither side ever waits for the other.
//

#ifndef SURROUND_CORE_H
#define SURROUND_CORE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
  SB_NUM_CHANNELS = 6,
  SB_NUM_EQ_BANDS = 5,
  SB_MAX_DELAY_MS = 200,
};

/// Channel order used everywhere (same as the "SoundPusher Audio" 5.1 device).
enum {
  SB_CH_FRONT_LEFT = 0,
  SB_CH_FRONT_RIGHT = 1,
  SB_CH_CENTER = 2,
  SB_CH_LFE = 3,
  SB_CH_SURROUND_LEFT = 4,
  SB_CH_SURROUND_RIGHT = 5,
};

enum {
  SB_FILTER_PEAK = 0,
  SB_FILTER_LOW_SHELF = 1,
  SB_FILTER_HIGH_SHELF = 2,
  SB_FILTER_HIGH_PASS = 3,
  SB_FILTER_LOW_PASS = 4,
};

enum {
  SB_TONE_PINK_NOISE = 0,
  SB_TONE_SINE = 1,
};

/// One band of the parametric equaliser.
typedef struct SBEQBand {
  int32_t type;   ///< one of SB_FILTER_*
  bool enabled;
  float freqHz;
  float gainDb;   ///< used by peak and shelf filters
  float q;        ///< width of the filter: higher = narrower
} SBEQBand;

/// Settings for one output channel (= one speaker).
typedef struct SBChannelParams {
  float gainDb;
  bool mute;
  bool solo;
  float delayMs;  ///< 0 ... SB_MAX_DELAY_MS
  SBEQBand eq[SB_NUM_EQ_BANDS];
} SBChannelParams;

/// The complete state of the processor.
typedef struct SBParams {
  bool bypass;          ///< true = pass audio through untouched
  float masterGainDb;
  /// routing[out][in] is the linear gain from input channel `in` to output channel `out` (may be negative to flip phase).
  float routing[SB_NUM_CHANNELS][SB_NUM_CHANNELS];
  SBChannelParams channels[SB_NUM_CHANNELS];
  SBEQBand masterEq[SB_NUM_EQ_BANDS];   ///< equaliser applied to every speaker, on top of each speaker's own

  bool bassEnabled;                      ///< bass management on/off
  float crossoverHz;
  bool bassFromChannel[SB_NUM_CHANNELS]; ///< which speakers have their lows moved to the subwoofer
  float bassRedirectGainDb;              ///< level of the moved bass (default -10 dB because decoders play LFE 10 dB louder)

  bool limiterEnabled;
  float limiterCeilingDb;
  float limiterReleaseMs;

  int32_t toneChannel;  ///< -1 = off, otherwise the speaker that plays the test signal (all other audio is silenced)
  int32_t toneType;     ///< SB_TONE_*
  float toneFreqHz;
  float toneLevelDb;
} SBParams;

// ---- parameter helpers (Swift sees C arrays as awkward tuples, so use these instead) ----
void sb_params_init_default(SBParams *params);
void sb_params_set_route(SBParams *params, int32_t outChannel, int32_t inChannel, float linearGain);
float sb_params_get_route(const SBParams *params, int32_t outChannel, int32_t inChannel);
SBChannelParams *sb_params_channel(SBParams *params, int32_t channel);
SBEQBand *sb_channel_band(SBChannelParams *channel, int32_t band);
SBEQBand *sb_params_master_band(SBParams *params, int32_t band);
void sb_params_set_bass_from(SBParams *params, int32_t channel, bool enabled);

// ---- engine ----
typedef struct SBEngine SBEngine;

SBEngine *sb_engine_create(double sampleRate);
void sb_engine_destroy(SBEngine *engine);
/// The one engine instance shared by the audio chain and the UI.
SBEngine *sb_shared_engine(void);

void sb_engine_set_sample_rate(SBEngine *engine, double sampleRate);
double sb_engine_sample_rate(SBEngine *engine);
void sb_engine_set_params(SBEngine *engine, const SBParams *params);

/// REAL-TIME: processes `numFrames` frames of interleaved 6-channel float audio. `input` and `output` may be the same buffer.
void sb_engine_process(SBEngine *engine, const float *input, float *output, uint32_t numFrames);

/// Peak level (linear, 0...1+) since the last call for this channel; reading resets it.
float sb_engine_take_input_peak(SBEngine *engine, int32_t channel);
float sb_engine_take_output_peak(SBEngine *engine, int32_t channel);
/// Largest amount (in dB, >= 0) the limiter turned the signal down since the last call.
float sb_engine_take_limiter_reduction_db(SBEngine *engine);

// ---- filter maths (also used to draw EQ curves) ----
/// Calculates biquad coefficients {b0, b1, b2, a1, a2} for a band. A disabled band gives the "do nothing" filter.
void sb_biquad_design(const SBEQBand *band, double sampleRate, double coeffs[5]);
/// Gain in dB of one biquad at a frequency.
double sb_biquad_magnitude_db(const double coeffs[5], double freqHz, double sampleRate);
/// Combined gain in dB of several EQ bands at a frequency.
double sb_eq_response_db(const SBEQBand *bands, int32_t numBands, double freqHz, double sampleRate);

#ifdef __cplusplus
}
#endif

#endif /* SURROUND_CORE_H */
