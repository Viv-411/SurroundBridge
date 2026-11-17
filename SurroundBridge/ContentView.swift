//
//  ContentView.swift
//  SurroundBridge
//
//  The main window: header bar on top, the room on the left, tabs on the right.
//

import SwiftUI

struct ContentView: View {
    @Environment(BridgeModel.self) private var model
    @State private var tab: Tab = {
        // normally starts on the first tab; the developer snapshot option can ask for another one
        Tab(rawValue: UserDefaults.standard.string(forKey: "SBSnapshot") ?? "") ?? .speakers
    }()

    enum Tab: String, CaseIterable, Identifiable {
        case speakers, routing, bass, room, settings
        var id: String { rawValue }

        var title: String {
            switch self {
            case .speakers: "Speakers"
            case .routing: "Routing"
            case .bass: "Bass"
            case .room: "Room"
            case .settings: "Settings"
            }
        }

        var icon: String {
            switch self {
            case .speakers: "hifispeaker.2.fill"
            case .routing: "point.3.connected.trianglepath.dotted"
            case .bass: "waveform.path.ecg"
            case .room: "sofa.fill"
            case .settings: "gearshape.fill"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar()
            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(spacing: 12) {
                        SpeakerLayoutView()
                        PositionCard()
                        TestToneControls()
                    }
                    .padding([.leading, .bottom], 16)
                    .padding(.trailing, 8)
                }
                .frame(width: 372)

                VStack(spacing: 0) {
                    tabBar
                    ScrollView {
                        Group {
                            switch tab {
                            case .speakers: SpeakersTab()
                            case .routing: RoutingTab()
                            case .bass: BassTab()
                            case .room: RoomTab()
                            case .settings: SettingsTab()
                            }
                        }
                        .padding(.leading, 8)
                        .padding([.trailing, .bottom], 16)
                    }
                }
            }
        }
        .frame(minWidth: 1060, minHeight: 660)
        .background(Theme.chassis)
        .foregroundStyle(Theme.text)
        .tint(Theme.signal)
        .fontDesign(Theme.current.rounded ? .rounded : .default)
        .preferredColorScheme(Theme.current.colorScheme)
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { item in
                let isSelected = tab == item
                Button { tab = item } label: {
                    Label(item.title, systemImage: item.icon)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(isSelected ? Theme.panel : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(isSelected ? Theme.signal : Theme.dim)
                        .fontWeight(isSelected ? .semibold : .regular)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.leading, 8)
        .padding(.bottom, 10)
    }
}

/// Name, connection status, presets, master volume and bypass.
struct HeaderBar: View {
    @Environment(BridgeModel.self) private var model
    @State private var isNamingPreset = false
    @State private var newPresetName = ""

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                SurroundGlyph().frame(width: 30, height: 30)
                Text("SurroundBridge").font(.title3.weight(.bold))
            }

            Button { AppController.shared.popUpOutputMenu() } label: {
                HStack(spacing: 7) {
                    Circle().fill(model.outputName == nil ? Theme.amber : Theme.signal).frame(width: 8, height: 8)
                    Text(model.outputName.map { "Playing to \($0)" } ?? "Not connected. Choose an output")
                    Image(systemName: "chevron.down").font(.caption2)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Theme.panel, in: Capsule())
            }
            .buttonStyle(.plain)
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
                Button("Save current settings as…") {
                    newPresetName = model.currentPresetName ?? ""
                    isNamingPreset = true
                }
                if let current = model.currentPresetName {
                    Button("Update “\(current)”") { model.savePreset(named: current) }
                    Button("Delete “\(current)”", role: .destructive) { model.deletePreset(named: current) }
                }
                Divider()
                Button("Reset sound settings to defaults") { model.resetToDefaults() }
            } label: {
                Label(model.currentPresetName ?? "Presets", systemImage: "slider.horizontal.3")
            }
            .fixedSize()

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill").foregroundStyle(Theme.dim)
                Slider(value: $model.state.masterGainDb, in: -40...6)
                    .frame(width: 160)
                    .accessibilityLabel("Master volume")
                ValueField(value: $model.state.masterGainDb, range: -40...6, unit: "dB", label: "Master volume")
            }
            .help("Master volume for all speakers")

            Toggle("Bypass", isOn: $model.state.bypass)
                .toggleStyle(.switch)
                .tint(Theme.amber)
                .help("Pass audio through untouched, to compare with and without processing")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .alert("Save preset", isPresented: $isNamingPreset) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") { model.savePreset(named: newPresetName) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Saves all speaker, EQ, routing and bass settings. Your room and seat are kept separately.")
        }
    }
}

/// Quick position controls under the room picture.
struct PositionCard: View {
    @Environment(BridgeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Card(title: "Where you sit") {
            HStack {
                Toggle("Adjust speakers for my position", isOn: $model.state.room.compensate)
                    .tint(Theme.amber)
                Spacer()
                Button("Reset") { model.resetListener() }
                    .help("Put “You” back in the middle of the room")
                    .accessibilityLabel("Reset my position")
            }
            if !model.state.room.spots.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 90), spacing: 6)], spacing: 6) {
                    ForEach(model.state.room.spots) { spot in
                        ChoiceButton(title: spot.name, isSelected: model.currentSpot == spot, tint: Theme.amber) {
                            model.goToSpot(spot)
                        }
                    }
                }
            }
            Hint(model.state.room.spots.isEmpty
                 ? "Drag the amber marker to your seat. Save spots like Desk or Bed in the Room tab."
                 : "Drag the amber marker, or pick a saved spot.")
        }
    }
}

/// Test signal buttons.
struct TestToneControls: View {
    @Environment(BridgeModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let isTestingSelected = model.toneSpeaker == model.selected && !model.isCyclingTone
        Card(title: "Speaker test") {
            HStack {
                Button {
                    model.toggleTone(on: model.selected)
                } label: {
                    Label(isTestingSelected ? "Stop" : "Test \(model.selected.short)",
                          systemImage: isTestingSelected ? "stop.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                Button {
                    if model.isCyclingTone { model.stopTone() } else { model.startCycle() }
                } label: {
                    Label(model.isCyclingTone ? "Stop" : "Test all", systemImage: model.isCyclingTone ? "stop.fill" : "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                }
            }
            Picker("Signal", selection: $model.toneType) {
                Text("Pink noise").tag(Int(SB_TONE_PINK_NOISE))
                Text("440 Hz tone").tag(Int(SB_TONE_SINE))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            LabeledSlider(title: "Level", value: $model.toneLevelDb, range: -40...(-6), titleWidth: 40)
            Hint("Other audio is silenced while a test plays. The subwoofer always gets a low hum.")
        }
    }
}
