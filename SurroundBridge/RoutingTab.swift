//
//  RoutingTab.swift
//  SurroundBridge
//
//  The routing matrix: which source channel plays from which speaker, and how loud.
//

import SwiftUI

struct RoutingTab: View {
    @Environment(BridgeModel.self) private var model
    @State private var selectedCell: Cell? = nil

    struct Cell: Equatable {
        var speaker: Int
        var source: Int
    }

    private var activePreset: RoutingPreset? {
        RoutingPreset.all.first { $0.matrix == model.state.routing }
    }

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            Card(title: "Sound Mode") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
                    ForEach(RoutingPreset.all) { preset in
                        let isActive = preset.matrix == model.state.routing
                        Button {
                            model.state.routing = preset.matrix
                        } label: {
                            Text(preset.name)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(isActive ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                        .help(preset.summary)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
                Text(activePreset?.summary ?? "Custom routing — edited by hand in the grid below.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "Routing Grid") {
                Text("Columns are what the Mac is playing (the source channels). Rows are your speakers. Click a square to connect or disconnect; select one to fine-tune it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Text("")
                        ForEach(Speaker.allCases) { source in
                            VStack(spacing: 0) {
                                Text(source.short).font(.caption.bold())
                                Text("source").font(.system(size: 9)).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(Speaker.allCases) { speaker in
                        GridRow {
                            Text("\(speaker.name)  →").font(.callout)
                                .gridColumnAlignment(.trailing)
                            ForEach(Speaker.allCases) { source in
                                cellView(speaker: speaker.rawValue, source: source.rawValue)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)

                if let cell = selectedCell {
                    Divider()
                    CellEditor(gain: $model.state.routing[cell.speaker][cell.source],
                               title: "\(Speaker(rawValue: cell.source)!.name) source  →  \(Speaker(rawValue: cell.speaker)!.name) speaker")
                }
            }
        }
    }

    private func cellView(speaker: Int, source: Int) -> some View {
        let gain = model.state.routing[speaker][source]
        let isOn = gain != 0
        let isSelected = selectedCell == Cell(speaker: speaker, source: source)
        let label: String = {
            guard isOn else { return "" }
            let db = 20 * log10(abs(gain))
            let text = abs(db) < 0.05 ? "0" : String(format: "%.0f", db)
            return (gain < 0 ? "ø " : "") + text
        }()
        return Button {
            if isSelected {
                // clicking the selected square again toggles the connection
                model.state.routing[speaker][source] = isOn ? 0 : 1
            } else {
                if !isOn { model.state.routing[speaker][source] = 1 }
                selectedCell = Cell(speaker: speaker, source: source)
            }
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(isOn ? Color.accentColor.opacity(0.25 + 0.6 * min(abs(gain), 1)) : Color.secondary.opacity(0.1))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(isSelected ? Color.primary : .clear, lineWidth: 2))
                .overlay(Text(label).font(.caption.monospacedDigit()).foregroundStyle(.white))
                .frame(width: 54, height: 34)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Disconnect") { model.state.routing[speaker][source] = 0 }
        }
        .accessibilityLabel("\(Speaker(rawValue: source)!.name) source to \(Speaker(rawValue: speaker)!.name) speaker")
        .accessibilityValue(isOn ? "\(label) decibels" : "off")
    }
}

/// Fine control for one square of the grid.
private struct CellEditor: View {
    @Binding var gain: Double
    let title: String

    private var levelDb: Binding<Double> {
        Binding(
            get: { gain == 0 ? -30 : min(max(20 * log10(abs(gain)), -30), 6) },
            set: { gain = (gain < 0 ? -1 : 1) * pow(10, $0 / 20) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.bold())
            HStack(spacing: 16) {
                Toggle("Connected", isOn: Binding(get: { gain != 0 }, set: { gain = $0 ? 1 : 0 }))
                Toggle("Flip phase", isOn: Binding(get: { gain < 0 }, set: { gain = abs(gain) * ($0 ? -1 : 1) }))
                    .disabled(gain == 0)
                    .help("Turns the waveform upside down. Used for difference signals like Matrix Surround.")
            }
            LabeledSlider(title: "Level", value: levelDb, range: -30...6, titleWidth: 50, format: formatDb)
                .disabled(gain == 0)
        }
    }
}
