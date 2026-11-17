//
//  Model.swift
//  SurroundBridge
//
//  The app's settings (what the UI edits) and how they are turned into parameters for the audio engine.
//

import Foundation
import Observation

/// The six speakers, in the channel order the audio engine uses.
enum Speaker: Int, CaseIterable, Identifiable, Codable {
    case frontLeft = 0, frontRight, center, sub, surroundLeft, surroundRight

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .frontLeft: "Front Left"
        case .frontRight: "Front Right"
        case .center: "Center"
        case .sub: "Subwoofer"
        case .surroundLeft: "Surround Left"
        case .surroundRight: "Surround Right"
        }
    }

    var short: String {
        switch self {
        case .frontLeft: "FL"
        case .frontRight: "FR"
        case .center: "C"
        case .sub: "SUB"
        case .surroundLeft: "SL"
        case .surroundRight: "SR"
        }
    }

    /// Order used when walking a test tone around the room.
    static let roomOrder: [Speaker] = [.frontLeft, .center, .frontRight, .surroundRight, .surroundLeft, .sub]
}

enum FilterType: Int, CaseIterable, Identifiable, Codable {
    case peak = 0, lowShelf, highShelf, highPass, lowPass

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .peak: "Bell"
        case .lowShelf: "Low Shelf"
        case .highShelf: "High Shelf"
        case .highPass: "High Pass"
        case .lowPass: "Low Pass"
        }
    }

    /// High/low pass filters only cut; they have no gain setting.
    var hasGain: Bool { self == .peak || self == .lowShelf || self == .highShelf }
}

struct EQBand: Codable, Equatable {
    var type: FilterType
    var enabled = false
    var freq: Double
    var gainDb = 0.0
    var q: Double

    static let defaults: [EQBand] = [
        EQBand(type: .lowShelf, freq: 60, q: 0.71),
        EQBand(type: .peak, freq: 250, q: 1),
        EQBand(type: .peak, freq: 1000, q: 1),
        EQBand(type: .peak, freq: 4000, q: 1),
        EQBand(type: .highShelf, freq: 12000, q: 0.71),
    ]

    var cBand: SBEQBand {
        SBEQBand(type: Int32(type.rawValue), enabled: enabled, freqHz: Float(freq), gainDb: Float(gainDb), q: Float(q))
    }
}

struct ChannelState: Codable, Equatable {
    var gainDb = 0.0
    var mute = false
    var solo = false
    var delayMs = 0.0
    var eq = EQBand.defaults
}

/// Ready-made equaliser curves. They work for one speaker or for the "All speakers" equaliser.
struct EQPreset: Identifiable {
    let name: String
    let bands: [EQBand]
    var id: String { name }

    private static func make(_ name: String, _ bands: [(FilterType, Double, Double, Double)?]) -> EQPreset {
        EQPreset(name: name, bands: zip(EQBand.defaults, bands).map { fallback, spec in
            guard let (type, freq, gain, q) = spec else { return fallback }
            return EQBand(type: type, enabled: true, freq: freq, gainDb: gain, q: q)
        })
    }

    static let all: [EQPreset] = [
        EQPreset(name: "Flat", bands: EQBand.defaults),
        make("Bass Boost", [(.lowShelf, 90, 5, 0.71), nil, nil, nil, nil]),
        make("Bass Cut", [(.lowShelf, 120, -6, 0.71), nil, nil, nil, nil]),
        make("Treble Boost", [nil, nil, nil, nil, (.highShelf, 8000, 4, 0.71)]),
        make("Loudness (quiet listening)", [(.lowShelf, 90, 5, 0.71), nil, nil, nil, (.highShelf, 9000, 4, 0.71)]),
        make("Warm", [(.lowShelf, 150, 3, 0.71), nil, nil, (.peak, 3500, -1.5, 1), (.highShelf, 8000, -3, 0.71)]),
        make("Bright", [nil, nil, nil, (.peak, 4500, 2, 1), (.highShelf, 9000, 4, 0.71)]),
        make("Rock", [(.lowShelf, 90, 4, 0.71), nil, (.peak, 700, -2.5, 0.9), (.peak, 3500, 2, 1), (.highShelf, 9000, 3, 0.71)]),
        make("Clear Dialogue", [(.lowShelf, 120, -2, 0.71), (.peak, 300, -2, 1), (.peak, 2200, 4, 0.8), nil, nil]),
        make("Night (less rumble)", [(.lowShelf, 140, -8, 0.71), nil, (.peak, 2000, 2, 0.8), nil, nil]),
        make("Voice Only (for center)", [(.highPass, 150, 0, 0.71), nil, (.peak, 2000, 3, 0.8), nil, (.lowPass, 7000, 0, 0.71)]),
    ]
}

struct Point2: Codable, Equatable {
    var x: Double
    var y: Double
}

/// A named place you listen from, e.g. "Desk" or "Bed".
struct ListeningSpot: Codable, Equatable, Identifiable {
    var name: String
    var position: Point2
    var id: String { name }
}

/// What the position feature adds to one speaker.
struct PositionAdjustment {
    var distanceM = 0.0
    var trimDb = 0.0
    var delayMs = 0.0
}

/// The room picture: where the speakers are, where you are, and how to compensate for it.
/// Positions are stored as fractions of the room (0...1 across, 0...1 from the TV wall to the back wall).
struct RoomState: Codable, Equatable {
    var compensate = false
    var adjustLevel = true
    var adjustDelay = true
    var widthM = 4.0
    var depthM = 4.5
    var speakers = RoomState.defaultSpeakers
    var listener = Point2(x: 0.5, y: 0.6)
    var spots: [ListeningSpot] = []

    static let defaultSpeakers: [Point2] = [
        Point2(x: 0.15, y: 0.14),   // front left
        Point2(x: 0.85, y: 0.14),   // front right
        Point2(x: 0.5, y: 0.1),     // center
        Point2(x: 0.3, y: 0.1),     // subwoofer
        Point2(x: 0.12, y: 0.86),   // surround left
        Point2(x: 0.88, y: 0.86),   // surround right
    ]

    static let speedOfSound = 343.0      // metres per second
    static let maxTrimDb = 15.0

    init() {}

    /// Tolerant decoding: settings saved by an older version simply keep the defaults for anything new.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RoomState()
        compensate = (try? c.decodeIfPresent(Bool.self, forKey: .compensate)) ?? d.compensate
        adjustLevel = (try? c.decodeIfPresent(Bool.self, forKey: .adjustLevel)) ?? d.adjustLevel
        adjustDelay = (try? c.decodeIfPresent(Bool.self, forKey: .adjustDelay)) ?? d.adjustDelay
        widthM = (try? c.decodeIfPresent(Double.self, forKey: .widthM)) ?? d.widthM
        depthM = (try? c.decodeIfPresent(Double.self, forKey: .depthM)) ?? d.depthM
        let saved = (try? c.decodeIfPresent([Point2].self, forKey: .speakers)) ?? d.speakers
        speakers = saved.count == 6 ? saved : d.speakers
        listener = (try? c.decodeIfPresent(Point2.self, forKey: .listener)) ?? d.listener
        spots = (try? c.decodeIfPresent([ListeningSpot].self, forKey: .spots)) ?? d.spots
    }

    /// Straight-line distance in metres from the listener to a speaker.
    func distance(to speaker: Int) -> Double {
        let dx = (speakers[speaker].x - listener.x) * widthM
        let dy = (speakers[speaker].y - listener.y) * depthM
        return max((dx * dx + dy * dy).squareRoot(), 0.3)
    }

    /// Works out how much quieter and later each speaker must play so that, where you sit,
    /// all speakers are equally loud and their sound arrives at the same moment.
    ///  - Timing: sound travels 343 m/s, so nearer speakers are held back until the farthest one has "caught up".
    ///  - Volume: sound gets about 6 dB quieter each time the distance doubles, so nearer speakers are turned down
    ///    to match the farthest one. (The subwoofer is left alone: deep bass fills a room far more evenly.)
    func adjustments() -> [PositionAdjustment] {
        let distances = (0..<6).map { distance(to: $0) }
        var result = distances.map { PositionAdjustment(distanceM: $0) }
        guard compensate else { return result }
        let farthest = distances.max() ?? 1
        let farthestMain = distances.enumerated().filter { $0.offset != Speaker.sub.rawValue }.map(\.element).max() ?? 1
        for i in 0..<6 {
            if adjustDelay {
                result[i].delayMs = (farthest - distances[i]) / Self.speedOfSound * 1000
            }
            if adjustLevel && i != Speaker.sub.rawValue {
                result[i].trimDb = max(20 * log10(distances[i] / farthestMain), -Self.maxTrimDb)
            }
        }
        return result
    }
}

/// Everything that makes up "how it sounds". This is what presets save and load.
struct BridgeState: Codable, Equatable {
    var bypass = false
    var masterGainDb = 0.0
    /// routing[speaker][source]: how much of each source channel goes to each speaker (1 = full, 0 = none, negative = phase flipped).
    var routing = RoutingPreset.direct.matrix
    var channels = [ChannelState](repeating: ChannelState(), count: Speaker.allCases.count)
    /// Equaliser applied to every speaker, on top of each speaker's own.
    var masterEQ = EQBand.defaults
    var room = RoomState()

    /// On by default: stereo sources (music) have no subwoofer channel, so without this the sub channel stays empty.
    var bassEnabled = true
    var crossoverHz = 100.0
    var bassFrom = Speaker.allCases.map { $0 != .sub }
    var bassRedirectDb = -10.0

    var limiterEnabled = true
    var limiterCeilingDb = -1.0
    var limiterReleaseMs = 100.0

    init() {}

    /// Tolerant decoding, so settings and presets saved by an older version still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BridgeState()
        bypass = (try? c.decodeIfPresent(Bool.self, forKey: .bypass)) ?? d.bypass
        masterGainDb = (try? c.decodeIfPresent(Double.self, forKey: .masterGainDb)) ?? d.masterGainDb
        routing = (try? c.decodeIfPresent([[Double]].self, forKey: .routing)) ?? d.routing
        channels = (try? c.decodeIfPresent([ChannelState].self, forKey: .channels)) ?? d.channels
        masterEQ = (try? c.decodeIfPresent([EQBand].self, forKey: .masterEQ)) ?? d.masterEQ
        room = (try? c.decodeIfPresent(RoomState.self, forKey: .room)) ?? d.room
        bassEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .bassEnabled)) ?? d.bassEnabled
        crossoverHz = (try? c.decodeIfPresent(Double.self, forKey: .crossoverHz)) ?? d.crossoverHz
        bassFrom = (try? c.decodeIfPresent([Bool].self, forKey: .bassFrom)) ?? d.bassFrom
        bassRedirectDb = (try? c.decodeIfPresent(Double.self, forKey: .bassRedirectDb)) ?? d.bassRedirectDb
        limiterEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .limiterEnabled)) ?? d.limiterEnabled
        limiterCeilingDb = (try? c.decodeIfPresent(Double.self, forKey: .limiterCeilingDb)) ?? d.limiterCeilingDb
        limiterReleaseMs = (try? c.decodeIfPresent(Double.self, forKey: .limiterReleaseMs)) ?? d.limiterReleaseMs
    }

    /// Converts to the plain C struct the audio engine understands.
    func makeParams(tone: Speaker?, toneType: Int, toneLevelDb: Double) -> SBParams {
        var p = SBParams()
        sb_params_init_default(&p)
        p.bypass = bypass
        p.masterGainDb = Float(masterGainDb)
        let position = room.adjustments()
        for (b, band) in masterEQ.prefix(Int(SB_NUM_EQ_BANDS)).enumerated() {
            sb_params_master_band(&p, Int32(b)).pointee = band.cBand
        }
        for out in 0..<6 {
            for src in 0..<6 {
                sb_params_set_route(&p, Int32(out), Int32(src), Float(routing[out][src]))
            }
            let ch = sb_params_channel(&p, Int32(out))!
            // your own setting plus whatever the listening-position feature adds
            ch.pointee.gainDb = Float(channels[out].gainDb + position[out].trimDb)
            ch.pointee.mute = channels[out].mute
            ch.pointee.solo = channels[out].solo
            ch.pointee.delayMs = Float(min(channels[out].delayMs + position[out].delayMs, Double(SB_MAX_DELAY_MS)))
            for (b, band) in channels[out].eq.prefix(Int(SB_NUM_EQ_BANDS)).enumerated() {
                sb_channel_band(ch, Int32(b)).pointee = band.cBand
            }
            sb_params_set_bass_from(&p, Int32(out), bassFrom[out])
        }
        p.bassEnabled = bassEnabled
        p.crossoverHz = Float(crossoverHz)
        p.bassRedirectGainDb = Float(bassRedirectDb)
        p.limiterEnabled = limiterEnabled
        p.limiterCeilingDb = Float(limiterCeilingDb)
        p.limiterReleaseMs = Float(limiterReleaseMs)
        p.toneChannel = Int32(tone?.rawValue ?? -1)
        p.toneType = Int32(toneType)
        p.toneLevelDb = Float(toneLevelDb)
        return p
    }

    /// Guards against broken preset files (wrong array sizes would crash the UI).
    var isWellFormed: Bool {
        routing.count == 6 && routing.allSatisfy { $0.count == 6 } && channels.count == 6
            && channels.allSatisfy { $0.eq.count == Int(SB_NUM_EQ_BANDS) } && bassFrom.count == 6
            && masterEQ.count == Int(SB_NUM_EQ_BANDS) && room.speakers.count == 6
    }
}

/// Ready-made routing layouts, like the sound modes on an AV receiver.
struct RoutingPreset: Identifiable {
    let name: String
    let summary: String
    let matrix: [[Double]]

    var id: String { name }

    private static func build(_ routes: [(Speaker, Speaker, Double)]) -> [[Double]] {
        var m = [[Double]](repeating: [Double](repeating: 0, count: 6), count: 6)
        for (speaker, source, gain) in routes { m[speaker.rawValue][source.rawValue] = gain }
        return m
    }

    private static let straight: [(Speaker, Speaker, Double)] = Speaker.allCases.map { ($0, $0, 1.0) }
    private static let half = 0.5
    private static let minus3dB = 0.707

    static let direct = RoutingPreset(
        name: "Direct 5.1",
        summary: "Every channel goes to its own speaker, untouched. Stereo sources play from the front pair only.",
        matrix: build(straight))

    static let all: [RoutingPreset] = [
        direct,
        RoutingPreset(
            name: "All Channel Stereo",
            summary: "Left also plays from the left surround, right from the right surround, and the center gets a mix of both. Fills the room with stereo music.",
            matrix: build(straight + [
                (.surroundLeft, .frontLeft, 1), (.surroundRight, .frontRight, 1),
                (.center, .frontLeft, half), (.center, .frontRight, half),
            ])),
        RoutingPreset(
            name: "Matrix Surround",
            summary: "Center gets what left and right share; the surrounds get only what differs between them (echoes, ambience). A classic Pro Logic-style upmix.",
            matrix: build(straight + [
                (.center, .frontLeft, half), (.center, .frontRight, half),
                (.surroundLeft, .frontLeft, half), (.surroundLeft, .frontRight, -half),
                (.surroundRight, .frontRight, half), (.surroundRight, .frontLeft, -half),
            ])),
        RoutingPreset(
            name: "Stereo 2.0",
            summary: "Everything is folded down to the two front speakers. Subwoofer silent.",
            matrix: build([
                (.frontLeft, .frontLeft, 1), (.frontLeft, .center, minus3dB), (.frontLeft, .surroundLeft, minus3dB),
                (.frontRight, .frontRight, 1), (.frontRight, .center, minus3dB), (.frontRight, .surroundRight, minus3dB),
            ])),
        RoutingPreset(
            name: "Stereo 2.1",
            summary: "Front pair plus subwoofer. Turn on bass management to give the sub the low end of music.",
            matrix: build([
                (.frontLeft, .frontLeft, 1), (.frontLeft, .center, minus3dB), (.frontLeft, .surroundLeft, minus3dB),
                (.frontRight, .frontRight, 1), (.frontRight, .center, minus3dB), (.frontRight, .surroundRight, minus3dB),
                (.sub, .sub, 1),
            ])),
        RoutingPreset(
            name: "Front Stage 3.1",
            summary: "Surround channels are folded into the front speakers; the surround speakers stay silent.",
            matrix: build([
                (.frontLeft, .frontLeft, 1), (.frontLeft, .surroundLeft, minus3dB),
                (.frontRight, .frontRight, 1), (.frontRight, .surroundRight, minus3dB),
                (.center, .center, 1), (.sub, .sub, 1),
            ])),
        RoutingPreset(
            name: "Phantom Center",
            summary: "The center channel is shared between front left and right instead of using the center speaker.",
            matrix: build(straight.filter { $0.0 != .center } + [
                (.frontLeft, .center, minus3dB), (.frontRight, .center, minus3dB),
            ])),
        RoutingPreset(
            name: "5-Channel Mono",
            summary: "The same mono mix from every speaker. Good for background music heard from anywhere in the room.",
            matrix: build(
                [Speaker.frontLeft, .frontRight, .center, .surroundLeft, .surroundRight].flatMap { speaker in
                    [(speaker, Speaker.frontLeft, half), (speaker, .frontRight, half), (speaker, .center, half),
                     (speaker, .surroundLeft, 0.35), (speaker, .surroundRight, 0.35)]
                } + [(.sub, .sub, 1)])),
    ]
}

/// The single source of truth for the UI. Any change to `state` is pushed to the audio engine straight away.
@Observable
final class BridgeModel {
    static let shared = BridgeModel()

    var state: BridgeState {
        didSet {
            guard state != oldValue else { return }
            pushToEngine()
            scheduleSave()
        }
    }

    /// Speaker currently playing the test signal (nil = off). Not saved in presets.
    var toneSpeaker: Speaker? { didSet { pushToEngine() } }
    var toneType = Int(SB_TONE_PINK_NOISE) { didSet { pushToEngine() } }
    var toneLevelDb = -20.0 { didSet { pushToEngine() } }
    var isCyclingTone = false

    var selected: Speaker = .frontLeft
    var presetNames: [String] = []
    var currentPresetName: String?
    /// Name of the device we are sending to, nil when no chain is running.
    var outputName: String?

    private var saveWork: DispatchWorkItem?
    private var cycleTask: Task<Void, Never>?
    private static let stateKey = "CurrentState"

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.stateKey),
           let saved = try? JSONDecoder().decode(BridgeState.self, from: data), saved.isWellFormed {
            state = saved
        } else {
            state = BridgeState()
        }
        // One-time update for settings saved before bass management became the default.
        let migrationKey = "DidEnableBassManagementByDefault"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            state.bassEnabled = true
            state.crossoverHz = 100
            UserDefaults.standard.set(true, forKey: migrationKey)
            scheduleSave()
        }
        pushToEngine()
        refreshPresets()
    }

    var sampleRate: Double { sb_engine_sample_rate(sb_shared_engine()) }

    // MARK: sound modes

    func isActive(_ preset: RoutingPreset) -> Bool { state.routing == preset.matrix }

    func apply(_ preset: RoutingPreset) { state.routing = preset.matrix }

    // MARK: listening position

    /// True while the speakers in the room picture can be dragged to match the real room.
    var isArrangingSpeakers = false

    func saveSpot(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state.room.spots.removeAll { $0.name == trimmed }
        state.room.spots.append(ListeningSpot(name: trimmed, position: state.room.listener))
    }

    /// Moves "you" to a saved spot and turns the position adjustment on.
    func goToSpot(_ spot: ListeningSpot) {
        var room = state.room
        room.listener = spot.position
        room.compensate = true
        state.room = room
    }

    var currentSpot: ListeningSpot? {
        state.room.spots.first { $0.position == state.room.listener }
    }

    /// Developer aid for window pictures: an example state that is never written to disk.
    func loadDemoStateForSnapshot() {
        isSnapshotDemo = true
        var demo = state
        demo.room.compensate = true
        demo.room.listener = Point2(x: 0.62, y: 0.34)
        demo.room.spots = [ListeningSpot(name: "Desk", position: demo.room.listener),
                           ListeningSpot(name: "Bed", position: Point2(x: 0.5, y: 0.8))]
        demo.masterEQ = EQPreset.all.first { $0.name == "Rock" }?.bands ?? demo.masterEQ
        state = demo
    }
    private var isSnapshotDemo = false

    private func pushToEngine() {
        var params = state.makeParams(tone: toneSpeaker, toneType: toneType, toneLevelDb: toneLevelDb)
        sb_engine_set_params(sb_shared_engine(), &params)
    }

    /// Writes the settings to disk shortly after the last change (not on every slider tick).
    private func scheduleSave() {
        guard !isSnapshotDemo else { return }
        saveWork?.cancel()
        let snapshot = state
        let work = DispatchWorkItem {
            if let data = try? JSONEncoder().encode(snapshot) {
                UserDefaults.standard.set(data, forKey: Self.stateKey)
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: test tone

    func toggleTone(on speaker: Speaker) {
        stopCycle()
        toneSpeaker = toneSpeaker == speaker ? nil : speaker
    }

    /// Plays the test signal on each speaker in turn, once around the room.
    func startCycle() {
        stopCycle()
        isCyclingTone = true
        cycleTask = Task { @MainActor [weak self] in
            for speaker in Speaker.roomOrder {
                guard let self, !Task.isCancelled else { return }
                self.toneSpeaker = speaker
                self.selected = speaker
                try? await Task.sleep(for: .seconds(2))
            }
            guard let self, !Task.isCancelled else { return }
            self.toneSpeaker = nil
            self.isCyclingTone = false
        }
    }

    func stopCycle() {
        cycleTask?.cancel()
        cycleTask = nil
        isCyclingTone = false
    }

    func stopTone() {
        stopCycle()
        toneSpeaker = nil
    }

    // MARK: presets (one JSON file each)

    private var presetFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let folder = base.appendingPathComponent("SurroundBridge/Presets", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func presetURL(_ name: String) -> URL {
        let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return presetFolder.appendingPathComponent(safe).appendingPathExtension("json")
    }

    func refreshPresets() {
        let files = (try? FileManager.default.contentsOfDirectory(at: presetFolder, includingPropertiesForKeys: nil)) ?? []
        presetNames = files.filter { $0.pathExtension == "json" }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    @discardableResult
    func savePreset(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state), (try? data.write(to: presetURL(trimmed))) != nil else { return false }
        currentPresetName = trimmed
        refreshPresets()
        return true
    }

    func loadPreset(named name: String) {
        guard let data = try? Data(contentsOf: presetURL(name)),
              let loaded = try? JSONDecoder().decode(BridgeState.self, from: data), loaded.isWellFormed else { return }
        var new = loaded
        new.room = state.room      // presets change the sound, not where your speakers and seat are
        state = new
        currentPresetName = name
    }

    func deletePreset(named name: String) {
        try? FileManager.default.removeItem(at: presetURL(name))
        if currentPresetName == name { currentPresetName = nil }
        refreshPresets()
    }

    func resetToDefaults() {
        var new = BridgeState()
        new.room = state.room
        state = new
        currentPresetName = nil
    }
}

/// Live level meters. Kept separate from BridgeModel so that 30 updates a second only redraw the meters.
@Observable
final class MeterModel {
    static let shared = MeterModel()

    /// 0...1 where 1 = full scale (0 dBFS) and 0 = -60 dB or quieter.
    var input = [Double](repeating: 0, count: 6)
    var output = [Double](repeating: 0, count: 6)
    var limiterReductionDb = 0.0

    private var timer: Timer?

    static func normalized(_ linear: Float) -> Double {
        guard linear > 0 else { return 0 }
        let db = 20 * log10(Double(linear))
        return min(max((db + 60) / 60, 0), 1)
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)   // .common keeps meters moving while a slider is being dragged
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let engine = sb_shared_engine()
        for c in 0..<6 {
            // jump up instantly, fall back slowly (like a hardware meter)
            input[c] = max(Self.normalized(sb_engine_take_input_peak(engine, Int32(c))), input[c] - 0.03)
            output[c] = max(Self.normalized(sb_engine_take_output_peak(engine, Int32(c))), output[c] - 0.03)
        }
        limiterReductionDb = max(Double(sb_engine_take_limiter_reduction_db(engine)), limiterReductionDb - 0.5)
    }
}
