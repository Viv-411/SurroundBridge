//
//  SpeakersTab.swift
//  SurroundBridge
//
//  Per-speaker volume, mute, solo and delay, plus the equaliser (for all speakers, or just the selected one).
//

import SwiftUI

struct SpeakersTab: View {
    @Environment(BridgeModel.self) private var model
    @State private var eqTarget = EQTarget.master

    enum EQTarget { case master, speaker }

    var body: some View {
        @Bindable var model = model
        let editingMaster = eqTarget == .master
        let bands = editingMaster ? $model.state.masterEQ : $model.state.channels[model.selected.rawValue].eq

        VStack(spacing: 12) {
            Card(title: "Speakers") {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Speaker").frame(width: 150, alignment: .leading)
                        Text("Level").frame(width: 60, alignment: .leading)
                        Text("Volume").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Delay").frame(width: 112, alignment: .leading)
                    }
                    .font(.caption).foregroundStyle(Theme.dim)

                    ForEach(Speaker.allCases) { speaker in
                        ChannelRow(speaker: speaker, channel: $model.state.channels[speaker.rawValue])
                    }
                }
                Hint(model.state.room.compensate
                     ? "Position adjustment is on, so each speaker also gets the extra volume trim and delay listed in the Room tab."
                     : "Delay holds a speaker back by a few milliseconds. Turn on “Adjust speakers for my position” to have it worked out from your room.")
            }

            Card(title: "Equaliser") {
                Menu("Presets") {
                    ForEach(EQPreset.all) { preset in
                        Button(preset.name) { bands.wrappedValue = preset.bands }
                    }
                }
                .fixedSize()
                .help("Ready-made curves for the equaliser you are editing")
            } content: {
                HStack(spacing: 6) {
                    ChoiceButton(title: "All speakers", isSelected: editingMaster) { eqTarget = .master }
                    ChoiceButton(title: "\(model.selected.name) only", isSelected: !editingMaster) { eqTarget = .speaker }
                }
                .frame(maxWidth: 420)

                EQEditor(bands: bands,
                         alsoApplied: editingMaster ? nil : model.state.masterEQ,
                         sampleRate: model.sampleRate)

                Hint(editingMaster
                     ? "This equaliser shapes every speaker. Each speaker can have its own on top: select a speaker, then choose “\(model.selected.name) only”."
                     : "This equaliser shapes only \(model.selected.name), on top of the All speakers equaliser. The dashed line shows the two combined.")
            }
        }
    }
}

private struct ChannelRow: View {
    @Environment(BridgeModel.self) private var model
    @Environment(MeterModel.self) private var meters
    let speaker: Speaker
    @Binding var channel: ChannelState

    var body: some View {
        let isSelected = model.selected == speaker
        HStack(spacing: 10) {
            Button { model.selected = speaker } label: {
                HStack(spacing: 7) {
                    Text(speaker.short).font(.caption.bold()).frame(width: 32)
                        .padding(.vertical, 3)
                        .background(isSelected ? Theme.signal : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(isSelected ? Theme.onSignal : Theme.text)
                    Text(speaker.name).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 150)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            LevelMeter(level: meters.output[speaker.rawValue]).frame(width: 60)

            Slider(value: $channel.gainDb, in: -30...12)
                .accessibilityLabel("\(speaker.name) volume")
            ValueField(value: $channel.gainDb, range: -30...12, unit: "dB", label: "\(speaker.name) volume")

            ToggleChip(label: "M", help: "Mute \(speaker.name)", isOn: $channel.mute, color: Theme.alert)
            ToggleChip(label: "S", help: "Solo \(speaker.name) (silences all others)", isOn: $channel.solo, color: Theme.amber)

            ValueField(value: $channel.delayMs, range: 0...Double(SB_MAX_DELAY_MS), unit: "ms", label: "\(speaker.name) delay")
            Stepper("Delay", value: $channel.delayMs, in: 0...Double(SB_MAX_DELAY_MS), step: 0.5).labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

/// The curve plus one row of controls per band.
struct EQEditor: View {
    @Binding var bands: [EQBand]
    /// Another equaliser that is heard together with this one (drawn as a dashed "combined" line).
    var alsoApplied: [EQBand]? = nil
    let sampleRate: Double

    var body: some View {
        VStack(spacing: 8) {
            EQCurveView(bands: $bands, alsoApplied: alsoApplied, sampleRate: sampleRate)
                .frame(height: 190)

            HStack(spacing: 8) {
                Text("On").frame(width: 44, alignment: .leading)
                Text("Shape").frame(width: 106, alignment: .leading)
                Text("Frequency").frame(maxWidth: .infinity, alignment: .leading)
                Text("Boost / cut").frame(maxWidth: .infinity, alignment: .leading)
                Text("Width (Q)").frame(width: 138, alignment: .leading)
            }
            .font(.caption).foregroundStyle(Theme.dim)

            ForEach(bands.indices, id: \.self) { index in
                EQBandRow(index: index, band: $bands[index])
            }
        }
    }
}

let eqBandColors: [Color] = [
    Color(red: 1.0, green: 0.45, blue: 0.45), Theme.amber, Color(red: 0.55, green: 0.85, blue: 0.45),
    Color(red: 0.45, green: 0.7, blue: 1.0), Color(red: 0.78, green: 0.6, blue: 1.0),
]

private struct EQBandRow: View {
    let index: Int
    @Binding var band: EQBand

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Toggle("Band \(index + 1)", isOn: $band.enabled)
                    .toggleStyle(.checkbox).labelsHidden()
                Circle().fill(eqBandColors[index % eqBandColors.count]).frame(width: 9, height: 9)
            }
            .frame(width: 44, alignment: .leading)

            Picker("Shape", selection: $band.type) {
                ForEach(FilterType.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 106)

            FrequencySlider(freq: $band.freq).accessibilityLabel("Band \(index + 1) frequency")
            ValueField(value: $band.freq, range: 20...20000, decimals: 0, unit: "Hz", width: 54, label: "Band \(index + 1) frequency")

            Slider(value: $band.gainDb, in: -18...18)
                .disabled(!band.type.hasGain)
                .accessibilityLabel("Band \(index + 1) boost or cut")
            ValueField(value: $band.gainDb, range: -18...18, unit: "dB", label: "Band \(index + 1) boost or cut")
                .disabled(!band.type.hasGain)
                .opacity(band.type.hasGain ? 1 : 0.4)

            Slider(value: $band.q, in: 0.3...8).frame(width: 70)
                .accessibilityLabel("Band \(index + 1) width")
            ValueField(value: $band.q, range: 0.1...20, decimals: 2, width: 46, label: "Band \(index + 1) width")
        }
        .opacity(band.enabled ? 1 : 0.6)
    }
}

/// Draws the combined frequency response and lets you drag each band.
struct EQCurveView: View {
    @Binding var bands: [EQBand]
    var alsoApplied: [EQBand]? = nil
    let sampleRate: Double

    private let minFreq = 20.0, maxFreq = 20000.0, dbRange = 18.0

    private func x(_ freq: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(log10(freq / minFreq) / log10(maxFreq / minFreq)) * width
    }
    private func y(_ db: Double, _ height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(min(max(db, -dbRange), dbRange) / dbRange) * (height / 2)
    }
    private func freq(atX x: CGFloat, _ width: CGFloat) -> Double {
        let t = min(max(Double(x / width), 0), 1)
        return minFreq * pow(maxFreq / minFreq, t)
    }
    private func db(atY y: CGFloat, _ height: CGFloat) -> Double {
        let value = Double((height / 2 - y) / (height / 2)) * dbRange
        return min(max(value, -dbRange), dbRange)
    }

    /// The response of some bands as a path, using the engine's own filter maths.
    private func curve(for bands: [EQBand], in size: CGSize) -> Path {
        var cBands = bands.map(\.cBand)
        let steps = 220
        var path = Path()
        for step in 0...steps {
            let f = minFreq * pow(maxFreq / minFreq, Double(step) / Double(steps))
            let gain = sb_eq_response_db(&cBands, Int32(cBands.count), f, sampleRate)
            let point = CGPoint(x: x(f, size.width), y: y(gain, size.height))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Canvas { context, size in
                    // grid: vertical lines at round frequencies, horizontal lines every 6 dB
                    var grid = Path()
                    for f in [50.0, 100, 200, 500, 1000, 2000, 5000, 10000] {
                        grid.move(to: CGPoint(x: x(f, size.width), y: 0))
                        grid.addLine(to: CGPoint(x: x(f, size.width), y: size.height))
                    }
                    for level in stride(from: -12.0, through: 12.0, by: 6.0) {
                        grid.move(to: CGPoint(x: 0, y: y(level, size.height)))
                        grid.addLine(to: CGPoint(x: size.width, y: y(level, size.height)))
                    }
                    context.stroke(grid, with: .color(Theme.line.opacity(0.7)), lineWidth: 0.5)

                    var zero = Path()
                    zero.move(to: CGPoint(x: 0, y: size.height / 2))
                    zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(zero, with: .color(Theme.dim.opacity(0.7)), lineWidth: 1)

                    for (f, label) in [(100.0, "100 Hz"), (1000, "1 kHz"), (10000, "10 kHz")] {
                        context.draw(Text(label).font(.caption2).foregroundStyle(Theme.dim),
                                     at: CGPoint(x: x(f, size.width) + 3, y: size.height - 8), anchor: .leading)
                    }
                    for level in [-12.0, 12.0] {
                        context.draw(Text(level > 0 ? "+12 dB" : "−12 dB").font(.caption2).foregroundStyle(Theme.dim),
                                     at: CGPoint(x: 4, y: y(level, size.height) - 7), anchor: .leading)
                    }

                    if let alsoApplied, alsoApplied.contains(where: \.enabled) {
                        context.stroke(curve(for: bands + alsoApplied, in: size), with: .color(Theme.text.opacity(0.6)),
                                       style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                    }

                    let line = curve(for: bands, in: size)
                    var fill = line
                    fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(Theme.signal.opacity(0.16)))
                    context.stroke(line, with: .color(Theme.signal), lineWidth: 2)
                }

                ForEach(bands.indices, id: \.self) { index in
                    if bands[index].enabled {
                        let band = bands[index]
                        Circle()
                            .fill(eqBandColors[index % eqBandColors.count])
                            .overlay(Circle().strokeBorder(Theme.chassis, lineWidth: 2))
                            .frame(width: 16, height: 16)
                            .contentShape(Circle().inset(by: -8))
                            .position(x: x(min(max(band.freq, minFreq), maxFreq), size.width),
                                      y: y(band.type.hasGain ? band.gainDb : 0, size.height))
                            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("eqCurve")).onChanged { drag in
                                bands[index].freq = freq(atX: drag.location.x, size.width)
                                if bands[index].type.hasGain {
                                    bands[index].gainDb = db(atY: drag.location.y, size.height)
                                }
                            })
                            .accessibilityLabel("Band \(index + 1) handle")
                    }
                }
            }
            .coordinateSpace(name: "eqCurve")
        }
        .background(Theme.chassis, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
