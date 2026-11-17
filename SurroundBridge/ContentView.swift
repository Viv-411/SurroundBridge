//
//  ContentView.swift
//  SurroundBridge
//
//  The main window: header bar on top, speaker layout on the left, tabs on the right.
//

import SwiftUI

struct ContentView: View {
    @Environment(BridgeModel.self) private var model
    @State private var tab: Tab = {
        // normally starts on the first tab; the developer snapshot option can ask for another one
        switch UserDefaults.standard.string(forKey: "SBSnapshot") {
        case "routing": .routing
        case "bass": .bass
        default: .speakers
        }
    }()

    enum Tab: String, CaseIterable, Identifiable {
        case speakers = "Speakers & EQ"
        case routing = "Routing"
        case bass = "Bass & Protection"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 14) {
                    SpeakerLayoutView()
                    TestToneControls()
                    Spacer(minLength: 0)
                }
                .padding(16)
                .frame(width: 330)

                Divider()

                VStack(spacing: 0) {
                    Picker("Section", selection: $tab) {
                        ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .padding(12)

                    ScrollView {
                        Group {
                            switch tab {
                            case .speakers: SpeakersTab()
                            case .routing: RoutingTab()
                            case .bass: BassTab()
                            }
                        }
                        .padding([.horizontal, .bottom], 16)
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .opacity(model.state.bypass ? 0.85 : 1)
    }
}

/// Connection status, presets, master volume and bypass.
struct HeaderBar: View {
    @Environment(BridgeModel.self) private var model
    @State private var isNamingPreset = false
    @State private var newPresetName = ""

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 14) {
            Button { AppController.shared.popUpOutputMenu() } label: {
                HStack(spacing: 6) {
                    Circle().fill(model.outputName == nil ? Color.orange : Color.green).frame(width: 9, height: 9)
                    Text(model.outputName.map { "Playing to \($0)" } ?? "Not connected — choose output")
                    Image(systemName: "chevron.down").font(.caption2)
                }
            }
            .help("Choose which device receives the Dolby Digital signal")

            Menu {
                if model.presetNames.isEmpty {
                    Text("No saved presets yet")
                }
                ForEach(model.presetNames, id: \.self) { name in
                    Button { model.loadPreset(named: name) } label: {
                        if name == model.currentPresetName { Label(name, systemImage: "checkmark") } else { Text(name) }
                    }
                }
                Divider()
                Button("Save Current Settings As…") {
                    newPresetName = model.currentPresetName ?? ""
                    isNamingPreset = true
                }
                if let current = model.currentPresetName {
                    Button("Update “\(current)”") { model.savePreset(named: current) }
                    Button("Delete “\(current)”", role: .destructive) { model.deletePreset(named: current) }
                }
                Divider()
                Button("Reset Everything to Defaults") { model.resetToDefaults() }
            } label: {
                Label(model.currentPresetName ?? "Presets", systemImage: "slider.horizontal.3")
            }
            .fixedSize()

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.secondary)
                Slider(value: $model.state.masterGainDb, in: -40...6)
                    .frame(width: 170)
                    .accessibilityLabel("Master volume")
                Text(formatDb(model.state.masterGainDb))
                    .monospacedDigit().foregroundStyle(.secondary)
                    .frame(width: 70, alignment: .trailing)
            }
            .help("Master volume for all speakers")

            Toggle("Bypass", isOn: $model.state.bypass)
                .toggleStyle(.switch)
                .help("Pass audio through untouched, to compare with and without processing")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .alert("Save Preset", isPresented: $isNamingPreset) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") { model.savePreset(named: newPresetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves all speaker, EQ, routing and bass settings.")
        }
    }
}

/// Test signal buttons under the speaker layout.
struct TestToneControls: View {
    @Environment(BridgeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card(title: "Speaker Test") {
            HStack {
                Button {
                    model.toggleTone(on: model.selected)
                } label: {
                    Label(model.toneSpeaker == model.selected && !model.isCyclingTone ? "Stop" : "Test \(model.selected.short)",
                          systemImage: model.toneSpeaker == model.selected && !model.isCyclingTone ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    if model.isCyclingTone { model.stopTone() } else { model.startCycle() }
                } label: {
                    Label(model.isCyclingTone ? "Stop" : "Test All", systemImage: model.isCyclingTone ? "stop.fill" : "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            Picker("Signal", selection: $model.toneType) {
                Text("Pink noise").tag(Int(SB_TONE_PINK_NOISE))
                Text("440 Hz tone").tag(Int(SB_TONE_SINE))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LabeledSlider(title: "Level", value: $model.toneLevelDb, range: -40...(-6), titleWidth: 40, format: formatDb)
            Text("Other audio is silenced while a test plays. The subwoofer always gets a low hum.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
