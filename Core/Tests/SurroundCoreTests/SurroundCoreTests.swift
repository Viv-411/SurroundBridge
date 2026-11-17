import XCTest
import SurroundCore

/// Tests for the DSP maths. They feed known signals through the engine and check the result.
final class SurroundCoreTests: XCTestCase {
    let sampleRate = 48000.0
    let channels = Int(SB_NUM_CHANNELS)

    // MARK: helpers

    func defaultParams() -> SBParams {
        var p = SBParams()
        sb_params_init_default(&p)
        p.limiterEnabled = false   // most tests want to see the raw maths
        return p
    }

    /// Interleaved 6-channel buffer with a sine wave on the given input channels.
    func sine(freq: Double, amplitude: Float, on inputs: [Int], frames: Int) -> [Float] {
        var buf = [Float](repeating: 0, count: frames * channels)
        for n in 0..<frames {
            let v = amplitude * Float(sin(2 * Double.pi * freq * Double(n) / sampleRate))
            for c in inputs { buf[n * channels + c] = v }
        }
        return buf
    }

    /// Runs audio through a fresh engine in AC-3 sized blocks (like the real app does).
    func run(_ params: SBParams, input: [Float], blockSize: Int = 1536) -> [Float] {
        let engine = sb_engine_create(sampleRate)!
        defer { sb_engine_destroy(engine) }
        var p = params
        sb_engine_set_params(engine, &p)
        var output = [Float](repeating: 0, count: input.count)
        let frames = input.count / channels
        var pos = 0
        input.withUnsafeBufferPointer { inPtr in
            output.withUnsafeMutableBufferPointer { outPtr in
                while pos < frames {
                    let n = min(blockSize, frames - pos)
                    sb_engine_process(engine, inPtr.baseAddress! + pos * channels, outPtr.baseAddress! + pos * channels, UInt32(n))
                    pos += n
                }
            }
        }
        return output
    }

    func channel(_ c: Int, of buf: [Float]) -> [Float] {
        stride(from: c, to: buf.count, by: channels).map { buf[$0] }
    }

    /// Loudest sample in the second half (skips the start-up phase of filters and gain glides).
    func settledPeak(_ samples: [Float]) -> Float {
        samples[(samples.count / 2)...].map { abs($0) }.max() ?? 0
    }

    /// Average (RMS) level of the second half.
    func settledRMS(_ samples: [Float]) -> Float {
        let half = samples[(samples.count / 2)...]
        return sqrt(half.map { $0 * $0 }.reduce(0, +) / Float(half.count))
    }

    func db(_ linear: Float) -> Double { 20 * log10(Double(max(linear, 1e-9))) }

    // MARK: routing

    func testDefaultIsStraightThrough() {
        let input = sine(freq: 1000, amplitude: 0.5, on: [0, 2, 5], frames: 9600)
        let output = run(defaultParams(), input: input)
        for i in 0..<input.count { XCTAssertEqual(output[i], input[i], accuracy: 1e-6) }
    }

    func testBypassIsExact() {
        var p = defaultParams()
        p.bypass = true
        p.masterGainDb = -20            // must be ignored in bypass
        let input = sine(freq: 300, amplitude: 0.9, on: [1, 3], frames: 4800)
        XCTAssertEqual(run(p, input: input), input)
    }

    func testRoutingMatrixMixesAndScales() {
        var p = defaultParams()
        // send front-left input to the surround-left speaker at half volume, and to nowhere else
        sb_params_set_route(&p, 0, 0, 0)
        sb_params_set_route(&p, Int32(SB_CH_SURROUND_LEFT), 0, 0.5)
        let output = run(p, input: sine(freq: 1000, amplitude: 0.8, on: [0], frames: 9600))
        XCTAssertEqual(settledPeak(channel(Int(SB_CH_SURROUND_LEFT), of: output)), 0.4, accuracy: 0.002)
        for c in [0, 1, 2, 3, 5] { XCTAssertEqual(settledPeak(channel(c, of: output)), 0, accuracy: 1e-6) }
    }

    func testRoutingSumsSeveralInputs() {
        var p = defaultParams()
        // centre speaker = half of left + half of right
        sb_params_set_route(&p, Int32(SB_CH_CENTER), 0, 0.5)
        sb_params_set_route(&p, Int32(SB_CH_CENTER), 1, 0.5)
        let output = run(p, input: sine(freq: 500, amplitude: 0.6, on: [0, 1], frames: 9600))
        XCTAssertEqual(settledPeak(channel(Int(SB_CH_CENTER), of: output)), 0.6, accuracy: 0.002)
    }

    func testNegativeRouteCancels() {
        var p = defaultParams()
        // surround = left minus right: identical left/right content must cancel completely
        sb_params_set_route(&p, Int32(SB_CH_SURROUND_LEFT), 0, 1)
        sb_params_set_route(&p, Int32(SB_CH_SURROUND_LEFT), 1, -1)
        let output = run(p, input: sine(freq: 500, amplitude: 0.6, on: [0, 1], frames: 9600))
        XCTAssertEqual(settledPeak(channel(Int(SB_CH_SURROUND_LEFT), of: output)), 0, accuracy: 1e-6)
    }

    // MARK: volume / mute / solo

    func testChannelAndMasterGain() {
        var p = defaultParams()
        sb_params_channel(&p, 1).pointee.gainDb = -6
        p.masterGainDb = -6
        let output = run(p, input: sine(freq: 1000, amplitude: 1.0, on: [0, 1], frames: 9600))
        XCTAssertEqual(db(settledPeak(channel(0, of: output))), -6, accuracy: 0.05)
        XCTAssertEqual(db(settledPeak(channel(1, of: output))), -12, accuracy: 0.05)
    }

    func testMuteAndSolo() {
        var p = defaultParams()
        sb_params_channel(&p, 0).pointee.mute = true
        var output = run(p, input: sine(freq: 1000, amplitude: 0.5, on: [0, 1, 2], frames: 9600))
        XCTAssertEqual(settledPeak(channel(0, of: output)), 0, accuracy: 1e-6)
        XCTAssertEqual(settledPeak(channel(1, of: output)), 0.5, accuracy: 0.001)

        p = defaultParams()
        sb_params_channel(&p, 2).pointee.solo = true
        output = run(p, input: sine(freq: 1000, amplitude: 0.5, on: [0, 1, 2], frames: 9600))
        XCTAssertEqual(settledPeak(channel(0, of: output)), 0, accuracy: 1e-6)
        XCTAssertEqual(settledPeak(channel(1, of: output)), 0, accuracy: 1e-6)
        XCTAssertEqual(settledPeak(channel(2, of: output)), 0.5, accuracy: 0.001)
    }

    func testGainChangeGlidesWithoutJump() {
        // changing the volume mid-stream must not produce a sudden step (which would be heard as a click)
        let engine = sb_engine_create(sampleRate)!
        defer { sb_engine_destroy(engine) }
        var p = defaultParams()
        sb_engine_set_params(engine, &p)
        let block = [Float](repeating: 1.0, count: 1536 * channels)   // constant signal makes steps obvious
        var out = [Float](repeating: 0, count: block.count)
        sb_engine_process(engine, block, &out, 1536)
        sb_params_channel(&p, 0).pointee.gainDb = -20
        sb_engine_set_params(engine, &p)
        sb_engine_process(engine, block, &out, 1536)
        let ch0 = channel(0, of: out)
        let biggestStep = zip(ch0, ch0.dropFirst()).map { abs($0 - $1) }.max()!
        XCTAssertLessThan(biggestStep, 0.002)
        XCTAssertEqual(ch0.last!, 0.1, accuracy: 0.001)
    }

    // MARK: delay

    func testDelayShiftsByExactSampleCount() {
        var p = defaultParams()
        sb_params_channel(&p, 4).pointee.delayMs = 10      // 10 ms = 480 samples at 48 kHz
        var input = [Float](repeating: 0, count: 4800 * channels)
        input[100 * channels + 4] = 1.0                     // a single click at sample 100
        input[100 * channels + 0] = 1.0
        let output = run(p, input: input)
        XCTAssertEqual(channel(0, of: output).firstIndex(of: 1.0), 100)
        XCTAssertEqual(channel(4, of: output).firstIndex(of: 1.0), 580)
    }

    // MARK: EQ

    func testBiquadDesignMatchesTextbookValues() {
        var band = SBEQBand(type: Int32(SB_FILTER_PEAK), enabled: true, freqHz: 1000, gainDb: 6, q: 1)
        var coeffs = [Double](repeating: 0, count: 5)
        sb_biquad_design(&band, sampleRate, &coeffs)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 1000, sampleRate), 6, accuracy: 0.01)   // full boost at centre
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 20, sampleRate), 0, accuracy: 0.05)     // nothing far away
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 20000, sampleRate), 0, accuracy: 0.1)

        band = SBEQBand(type: Int32(SB_FILTER_LOW_PASS), enabled: true, freqHz: 1000, gainDb: 0, q: 0.7071)
        sb_biquad_design(&band, sampleRate, &coeffs)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 1000, sampleRate), -3.01, accuracy: 0.05) // -3 dB at cutoff
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 10, sampleRate), 0, accuracy: 0.01)

        band = SBEQBand(type: Int32(SB_FILTER_LOW_SHELF), enabled: true, freqHz: 200, gainDb: -9, q: 0.7071)
        sb_biquad_design(&band, sampleRate, &coeffs)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 10, sampleRate), -9, accuracy: 0.1)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 10000, sampleRate), 0, accuracy: 0.05)

        band = SBEQBand(type: Int32(SB_FILTER_HIGH_SHELF), enabled: true, freqHz: 5000, gainDb: 4, q: 0.7071)
        sb_biquad_design(&band, sampleRate, &coeffs)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 20000, sampleRate), 4, accuracy: 0.1)
        XCTAssertEqual(sb_biquad_magnitude_db(coeffs, 50, sampleRate), 0, accuracy: 0.05)

        band.enabled = false
        sb_biquad_design(&band, sampleRate, &coeffs)
        XCTAssertEqual(coeffs, [1, 0, 0, 0, 0])
    }

    func testEQAudioMatchesPredictedCurve() {
        // the level actually measured through the engine must match what the curve drawing predicts
        var p = defaultParams()
        let ch = sb_params_channel(&p, 0)!
        sb_channel_band(ch, 1).pointee = SBEQBand(type: Int32(SB_FILTER_PEAK), enabled: true, freqHz: 1000, gainDb: 9, q: 2)
        sb_channel_band(ch, 0).pointee = SBEQBand(type: Int32(SB_FILTER_LOW_SHELF), enabled: true, freqHz: 150, gainDb: -6, q: 0.7071)
        for freq in [60.0, 150, 500, 1000, 1400, 8000] {
            let output = run(p, input: sine(freq: freq, amplitude: 0.1, on: [0, 1], frames: 48000))
            let predicted = sb_eq_response_db(&ch.pointee.eq.0, 5, freq, sampleRate)
            // compare against the untouched channel 1, using RMS (average level) which is reliable at any frequency
            let measured = db(settledRMS(channel(0, of: output))) - db(settledRMS(channel(1, of: output)))
            XCTAssertEqual(measured, predicted, accuracy: 0.15, "at \(freq) Hz")
            XCTAssertEqual(db(settledRMS(channel(1, of: output))), db(0.1) - 3.01, accuracy: 0.05)   // other channel untouched
        }
    }

    func testMasterEQAppliesToEverySpeakerAndStacksWithChannelEQ() {
        var p = defaultParams()
        sb_params_master_band(&p, 2).pointee = SBEQBand(type: Int32(SB_FILTER_PEAK), enabled: true, freqHz: 1000, gainDb: 6, q: 1)
        // front left additionally has its own -4 dB at the same spot: the two should simply add up to +2 dB
        sb_channel_band(sb_params_channel(&p, 0), 2).pointee = SBEQBand(type: Int32(SB_FILTER_PEAK), enabled: true, freqHz: 1000, gainDb: -4, q: 1)
        let output = run(p, input: sine(freq: 1000, amplitude: 0.1, on: [0, 1, 2, 3, 4, 5], frames: 48000))
        let reference = db(0.1) - 3.01
        XCTAssertEqual(db(settledRMS(channel(0, of: output))) - reference, 2, accuracy: 0.1)
        for c in 1..<6 { XCTAssertEqual(db(settledRMS(channel(c, of: output))) - reference, 6, accuracy: 0.1) }
    }

    // MARK: bass management

    func testBassManagementMovesLowsToSubwoofer() {
        var p = defaultParams()
        p.bassEnabled = true
        p.crossoverHz = 100
        p.bassRedirectGainDb = 0
        let lfe = Int(SB_CH_LFE)

        // 30 Hz: well below the crossover -> leaves the main speaker, arrives at the sub
        var output = run(p, input: sine(freq: 30, amplitude: 0.5, on: [0], frames: 48000))
        XCTAssertLessThan(db(settledPeak(channel(0, of: output))) - db(0.5), -35)
        XCTAssertEqual(db(settledPeak(channel(lfe, of: output))) - db(0.5), 0, accuracy: 0.3)

        // 1 kHz: well above -> stays in the main speaker, sub gets (almost) nothing
        output = run(p, input: sine(freq: 1000, amplitude: 0.5, on: [0], frames: 48000))
        XCTAssertEqual(db(settledPeak(channel(0, of: output))) - db(0.5), 0, accuracy: 0.1)
        XCTAssertLessThan(db(settledPeak(channel(lfe, of: output))) - db(0.5), -60)

        // exactly at the crossover both sides are 6 dB down (the Linkwitz-Riley property)
        output = run(p, input: sine(freq: 100, amplitude: 0.5, on: [0], frames: 48000))
        XCTAssertEqual(db(settledPeak(channel(0, of: output))) - db(0.5), -6.02, accuracy: 0.2)
        XCTAssertEqual(db(settledPeak(channel(lfe, of: output))) - db(0.5), -6.02, accuracy: 0.2)
    }

    func testBassManagementRespectsSpeakerSelectionAndLevel() {
        var p = defaultParams()
        p.bassEnabled = true
        p.crossoverHz = 100
        p.bassRedirectGainDb = -10
        sb_params_set_bass_from(&p, 1, false)     // front right keeps its bass
        let output = run(p, input: sine(freq: 30, amplitude: 0.5, on: [1], frames: 48000))
        XCTAssertEqual(settledPeak(channel(1, of: output)), 0.5, accuracy: 0.005)
        XCTAssertEqual(settledPeak(channel(Int(SB_CH_LFE), of: output)), 0, accuracy: 1e-5)

        let moved = run(p, input: sine(freq: 30, amplitude: 0.5, on: [0], frames: 48000))
        XCTAssertEqual(db(settledPeak(channel(Int(SB_CH_LFE), of: moved))) - db(0.5), -10, accuracy: 0.3)
    }

    // MARK: limiter

    func testLimiterNeverExceedsCeiling() {
        var p = defaultParams()
        p.limiterEnabled = true
        p.limiterCeilingDb = -1
        p.masterGainDb = 12                        // push everything far too loud
        let ceiling = Float(pow(10.0, -1.0 / 20.0))
        var input = sine(freq: 220, amplitude: 1.0, on: [0, 1, 2, 3, 4, 5], frames: 48000)
        for n in stride(from: 5000, to: 48000, by: 7000) { input[n * channels + 2] = 4.0 }   // sudden spikes
        let output = run(p, input: input)
        XCTAssertLessThanOrEqual(output.map { abs($0) }.max()!, ceiling + 1e-6)
        // and it should still be loud, i.e. turned down rather than silenced
        XCTAssertGreaterThan(settledPeak(channel(0, of: output)), ceiling * 0.5)
    }

    func testLimiterLeavesQuietAudioAlone() {
        var p = defaultParams()
        p.limiterEnabled = true
        let input = sine(freq: 1000, amplitude: 0.5, on: [0], frames: 9600)
        let output = run(p, input: input)
        // identical apart from the limiter's small look-ahead delay (64 samples)
        let inCh = channel(0, of: input), outCh = channel(0, of: output)
        for n in 64..<inCh.count { XCTAssertEqual(outCh[n], inCh[n - 64], accuracy: 1e-6) }
    }

    func testLimiterReportsReduction() {
        let engine = sb_engine_create(sampleRate)!
        defer { sb_engine_destroy(engine) }
        var p = defaultParams()
        p.limiterEnabled = true
        p.limiterCeilingDb = -6
        sb_engine_set_params(engine, &p)
        let input = sine(freq: 500, amplitude: 1.0, on: [0], frames: 4800)
        var out = [Float](repeating: 0, count: input.count)
        sb_engine_process(engine, input, &out, 4800)
        XCTAssertEqual(Double(sb_engine_take_limiter_reduction_db(engine)), 6, accuracy: 0.5)
        XCTAssertEqual(sb_engine_take_limiter_reduction_db(engine), 0)     // reading resets it
    }

    // MARK: test tone and meters

    func testToneOnlyOnChosenSpeakerEvenWhenMuted() {
        var p = defaultParams()
        p.toneChannel = Int32(SB_CH_SURROUND_RIGHT)
        p.toneType = Int32(SB_TONE_SINE)
        p.toneLevelDb = -20
        sb_params_channel(&p, Int32(SB_CH_SURROUND_RIGHT)).pointee.mute = true
        let output = run(p, input: sine(freq: 1000, amplitude: 0.9, on: [0, 1, 2, 3, 4, 5], frames: 9600))
        XCTAssertEqual(db(settledPeak(channel(Int(SB_CH_SURROUND_RIGHT), of: output))), -20, accuracy: 0.1)
        for c in 0..<5 { XCTAssertEqual(settledPeak(channel(c, of: output)), 0, accuracy: 1e-6) }
    }

    func testPinkNoiseToneIsAudibleAndBounded() {
        var p = defaultParams()
        p.toneChannel = 0
        p.toneType = Int32(SB_TONE_PINK_NOISE)
        p.toneLevelDb = -20
        let out0 = channel(0, of: run(p, input: [Float](repeating: 0, count: 48000 * channels)))
        let rms = sqrt(out0.map { $0 * $0 }.reduce(0, +) / Float(out0.count))
        XCTAssertGreaterThan(rms, 0.005)
        XCTAssertLessThan(out0.map { abs($0) }.max()!, 0.5)
    }

    func testMetersReportPeaks() {
        let engine = sb_engine_create(sampleRate)!
        defer { sb_engine_destroy(engine) }
        var p = defaultParams()
        sb_params_channel(&p, 0).pointee.gainDb = -6
        sb_engine_set_params(engine, &p)
        let input = sine(freq: 1000, amplitude: 0.8, on: [0], frames: 4800)
        var out = [Float](repeating: 0, count: input.count)
        sb_engine_process(engine, input, &out, 1536)   // let the gain glide finish
        _ = sb_engine_take_output_peak(engine, 0)
        input.withUnsafeBufferPointer { sb_engine_process(engine, $0.baseAddress! + 1536 * channels, &out, 3000) }
        XCTAssertEqual(sb_engine_take_input_peak(engine, 0), 0.8, accuracy: 0.01)
        XCTAssertEqual(sb_engine_take_output_peak(engine, 0), 0.4, accuracy: 0.01)
        XCTAssertEqual(sb_engine_take_output_peak(engine, 1), 0)
    }

    func testHugeBlockIsSplitSafely() {
        // more frames in one call than the internal buffers hold
        let input = sine(freq: 1000, amplitude: 0.5, on: [0], frames: 20000)
        let output = run(defaultParams(), input: input, blockSize: 20000)
        for i in 0..<input.count { XCTAssertEqual(output[i], input[i], accuracy: 1e-6) }
    }
}
