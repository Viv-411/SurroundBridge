//
//  Controls.swift
//  SurroundBridge
//
//  Small reusable building blocks: level meter, labelled slider, formatting helpers.
//

import SwiftUI

func formatDb(_ value: Double) -> String {
    let rounded = (value * 10).rounded() / 10
    return (rounded > 0 ? "+" : "") + String(format: "%.1f dB", rounded)
}

func formatHz(_ value: Double) -> String {
    value >= 1000 ? String(format: "%.1f kHz", value / 1000) : String(format: "%.0f Hz", value)
}

/// Horizontal level meter. `level` is 0...1 (see MeterModel.normalized).
struct LevelMeter: View {
    var level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(LinearGradient(
                        stops: [.init(color: .green, location: 0), .init(color: .green, location: 0.75),
                                .init(color: .yellow, location: 0.9), .init(color: .red, location: 1)],
                        startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: max(0, geo.size.width * level))
                    }
            }
        }
        .frame(height: 6)
        .accessibilityLabel("Level")
        .accessibilityValue("\(Int(level * 100)) percent")
    }
}

/// Title on the left, slider in the middle, current value on the right.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var titleWidth: CGFloat = 110
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: titleWidth, alignment: .leading)
            if let step {
                Slider(value: $value, in: range, step: step)
            } else {
                Slider(value: $value, in: range)
            }
            Text(format(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Slider that moves in octaves instead of Hz, which is how we hear pitch.
struct FrequencySlider: View {
    @Binding var freq: Double
    var range: ClosedRange<Double> = 20...20000

    var body: some View {
        Slider(value: Binding(
            get: { log10(min(max(freq, range.lowerBound), range.upperBound)) },
            set: { freq = pow(10, $0) }),
            in: log10(range.lowerBound)...log10(range.upperBound))
    }
}

/// Small square on/off button used for Mute and Solo.
struct ToggleChip: View {
    let label: String
    let help: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Button { isOn.toggle() } label: {
            Text(label)
                .font(.caption.bold())
                .frame(width: 24, height: 22)
                .background(isOn ? color : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(isOn ? .white : .primary)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Section card with a title.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
