//
//  Controls.swift
//  SurroundBridge
//
//  Small reusable building blocks: level meter, sliders with a number box you can type into, cards.
//

import SwiftUI

/// Horizontal level meter. `level` is 0...1 (see MeterModel.normalized).
struct LevelMeter: View {
    var level: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.raised)
                Capsule()
                    .fill(LinearGradient(
                        stops: [.init(color: Theme.signal, location: 0), .init(color: Theme.signal, location: 0.75),
                                .init(color: Theme.amber, location: 0.9), .init(color: Theme.alert, location: 1)],
                        startPoint: .leading, endPoint: .trailing))
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

/// A number you can type. Press Return (or click elsewhere) to apply; the value is kept inside `range`.
struct ValueField: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var decimals = 1
    var unit = ""
    var width: CGFloat = 50
    var label = "Value"

    var body: some View {
        HStack(spacing: 4) {
            TextField(label, value: Binding(
                get: {
                    // round for display, and never show "-0"
                    let scale = pow(10.0, Double(decimals))
                    let rounded = (value * scale).rounded() / scale
                    return rounded == 0 ? 0 : rounded
                },
                set: { value = min(max($0, range.lowerBound), range.upperBound) }),
                format: .number.precision(.fractionLength(0...decimals)).grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                .frame(width: width)
                .accessibilityLabel(label)
            if !unit.isEmpty {
                Text(unit).font(.caption).foregroundStyle(Theme.dim).frame(width: 22, alignment: .leading)
            }
        }
        .help("Type a value from \(range.lowerBound.formatted()) to \(range.upperBound.formatted()) and press Return")
    }
}

/// Title on the left, slider in the middle, typeable value on the right.
struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double? = nil
    var titleWidth: CGFloat = 120
    var unit = "dB"
    var decimals = 1

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: titleWidth, alignment: .leading)
            if let step {
                Slider(value: $value, in: range, step: step).accessibilityLabel(title)
            } else {
                Slider(value: $value, in: range).accessibilityLabel(title)
            }
            ValueField(value: $value, range: range, decimals: decimals, unit: unit, label: title)
        }
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
                .background(isOn ? color : Theme.raised, in: RoundedRectangle(cornerRadius: 5))
                .foregroundStyle(isOn ? Theme.chassis : Theme.text)
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A selectable pill, used for sound modes, saved spots and similar choices.
struct ChoiceButton: View {
    let title: String
    let isSelected: Bool
    var tint = Theme.signal
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(isSelected ? tint : Theme.raised, in: RoundedRectangle(cornerRadius: 8))
                .foregroundStyle(isSelected ? Theme.chassis : Theme.text)
                .fontWeight(isSelected ? .semibold : .regular)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Small grey explanation text.
struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Section panel with a title.
struct Card<Content: View, Accessory: View>: View {
    let title: String
    @ViewBuilder var accessory: Accessory
    @ViewBuilder var content: Content

    init(title: String, @ViewBuilder accessory: () -> Accessory = { EmptyView() }, @ViewBuilder content: () -> Content) {
        self.title = title
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                accessory
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
    }
}
