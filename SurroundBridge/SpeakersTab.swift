//
//  SpeakersTab.swift
//  SurroundBridge
//
//  Per-speaker volume, mute, solo and delay, plus the equaliser for the selected speaker.
//

import SwiftUI

struct SpeakersTab: View {
    @Environment(BridgeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            Card(title: "Speakers") {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        Text("Speaker").frame(width: 150, alignment: .leading)
                        Text("Level").frame(width: 70, alignment: .leading)
                        Text("Volume").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Delay").frame(width: 150, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary)

                    ForEach(Speaker.allCases) { speaker in
                        ChannelRow(speaker: speaker, channel: $model.state.channels[speaker.rawValue])
                    }
                }
                Text("Delay holds a speaker back by a few milliseconds. Use it on speakers that are closer to you so every speaker's sound arrives at the same moment (about 3 ms per metre of difference).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "Equaliser — \(model.selected.name)") {
                EQEditor(bands: $model.state.channels[model.selected.rawValue].eq, sampleRate: model.sampleRate)
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
                HStack(spacing: 6) {
                    Text(speaker.short).font(.caption.bold()).frame(width: 30)
                        .padding(.vertical, 3)
                        .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                        .foregroundStyle(isSelected ? .white : .primary)
                    Text(speaker.name).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 150)
            .accessibilityAddTraits(isSelected ? .isSelected : [])

            LevelMeter(level: meters.output[speaker.rawValue]).frame(width: 70)

            Slider(value: $channel.gainDb, in: -30...12)
                .accessibilityLabel("\(speaker.name) volume")
            Text(formatDb(channel.gainDb))
                .monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 66, alignment: .trailing)

            ToggleChip(label: "M", help: "Mute \(speaker.name)", isOn: $channel.mute, color: .red)
            ToggleChip(label: "S", help: "Solo \(speaker.name) (silences all others)", isOn: $channel.solo, color: .orange)

            HStack(spacing: 4) {
                TextField("Delay", value: $channel.delayMs, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52)
                    .accessibilityLabel("\(speaker.name) delay in milliseconds")
                    .onChange(of: channel.delayMs) { _, new in
                        let clamped = min(max(new, 0), Double(SB_MAX_DELAY_MS))
                        if clamped != new { channel.delayMs = clamped }
                    }
                Text("ms").foregroundStyle(.secondary)
                Stepper("Delay", value: $channel.delayMs, in: 0...Double(SB_MAX_DELAY_MS), step: 0.5).labelsHidden()
            }
        }
        .padding(.vertical, 2)
    }
}

/// The curve plus one row of controls per band.
struct EQEditor: View {
    @Binding var bands: [EQBand]
    let sampleRate: Double

    var body: some View {
        VStack(spacing: 10) {
            EQCurveView(bands: $bands, sampleRate: sampleRate)
                .frame(height: 190)

            ForEach(bands.indices, id: \.self) { index in
                EQBandRow(index: index, band: $bands[index])
            }

            HStack {
                Text("Drag the dots on the curve, or use the sliders. Width (Q): higher = narrower.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Flatten") {
                    bands = EQBand.defaults
                }
                .help("Reset this speaker's equaliser")
            }
        }
    }
}

let eqBandColors: [Color] = [.red, .orange, .green, .blue, .purple]

private struct EQBandRow: View {
    let index: Int
    @Binding var band: EQBand

    var body: some View {
        HStack(spacing: 8) {
            Toggle("Band \(index + 1)", isOn: $band.enabled)
                .toggleStyle(.checkbox).labelsHidden()
            Circle().fill(eqBandColors[index % eqBandColors.count]).frame(width: 9, height: 9)
            Picker("Type", selection: $band.type) {
                ForEach(FilterType.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .frame(width: 106)

            FrequencySlider(freq: $band.freq).accessibilityLabel("Band \(index + 1) frequency")
            Text(formatHz(band.freq)).monospacedDigit().foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)

            Slider(value: $band.gainDb, in: -18...18)
                .disabled(!band.type.hasGain)
                .accessibilityLabel("Band \(index + 1) gain")
            Text(band.type.hasGain ? formatDb(band.gainDb) : "—").monospacedDigit().foregroundStyle(.secondary).frame(width: 62, alignment: .trailing)

            Slider(value: $band.q, in: 0.3...8).frame(width: 70)
                .accessibilityLabel("Band \(index + 1) width")
            Text(String(format: "Q %.1f", band.q)).monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
        }
        .opacity(band.enabled ? 1 : 0.55)
    }
}

/// Draws the combined frequency response and lets you drag each band.
struct EQCurveView: View {
    @Binding var bands: [EQBand]
    let sampleRate: Double

    private let minFreq = 20.0, maxFreq = 20000.0, dbRange = 18.0

    private func x(_ freq: Double, _ width: CGFloat) -> CGFloat {
        CGFloat(log10(freq / minFreq) / log10(maxFreq / minFreq)) * width
    }
    private func y(_ db: Double, _ height: CGFloat) -> CGFloat {
        height / 2 - CGFloat(db / dbRange) * (height / 2)
    }
    private func freq(atX x: CGFloat, _ width: CGFloat) -> Double {
        let t = min(max(Double(x / width), 0), 1)
        return minFreq * pow(maxFreq / minFreq, t)
    }
    private func db(atY y: CGFloat, _ height: CGFloat) -> Double {
        let value = Double((height / 2 - y) / (height / 2)) * dbRange
        return min(max(value, -dbRange), dbRange)
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
                    context.stroke(grid, with: .color(.secondary.opacity(0.22)), lineWidth: 0.5)

                    var zero = Path()
                    zero.move(to: CGPoint(x: 0, y: size.height / 2))
                    zero.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    context.stroke(zero, with: .color(.secondary.opacity(0.6)), lineWidth: 1)

                    for (f, label) in [(100.0, "100"), (1000, "1k"), (10000, "10k")] {
                        context.draw(Text(label).font(.caption2).foregroundStyle(.secondary),
                                     at: CGPoint(x: x(f, size.width) + 3, y: size.height - 8), anchor: .leading)
                    }
                    for level in [-12.0, 12.0] {
                        context.draw(Text(level > 0 ? "+12 dB" : "−12 dB").font(.caption2).foregroundStyle(.secondary),
                                     at: CGPoint(x: 4, y: y(level, size.height) - 7), anchor: .leading)
                    }

                    // the curve: ask the engine's own filter maths what the EQ does at each frequency
                    var cBands = bands.map(\.cBand)
                    let steps = 220
                    var curve = Path()
                    for step in 0...steps {
                        let f = minFreq * pow(maxFreq / minFreq, Double(step) / Double(steps))
                        let gain = sb_eq_response_db(&cBands, Int32(cBands.count), f, sampleRate)
                        let point = CGPoint(x: x(f, size.width), y: y(min(max(gain, -dbRange), dbRange), size.height))
                        if step == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
                    }
                    var fill = curve
                    fill.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                    fill.addLine(to: CGPoint(x: 0, y: size.height / 2))
                    fill.closeSubpath()
                    context.fill(fill, with: .color(.accentColor.opacity(0.15)))
                    context.stroke(curve, with: .color(.accentColor), lineWidth: 2)
                }

                ForEach(bands.indices, id: \.self) { index in
                    if bands[index].enabled {
                        let band = bands[index]
                        Circle()
                            .fill(eqBandColors[index % eqBandColors.count])
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .frame(width: 15, height: 15)
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
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}
