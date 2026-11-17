//
//  RoomTab.swift
//  SurroundBridge
//
//  Describe your room, then let the app balance the speakers for wherever you sit.
//

import SwiftUI

struct RoomTab: View {
    @Environment(BridgeModel.self) private var model
    @State private var newSpotName = ""

    var body: some View {
        @Bindable var model = model
        let room = model.state.room
        let adjustments = room.adjustments()

        VStack(spacing: 12) {
            Card(title: "Adjust for where you sit") {
                Toggle("Adjust speakers for my position", isOn: $model.state.room.compensate)
                    .tint(Theme.amber)
                Group {
                    Toggle("Even out the volume (nearer speakers play quieter)", isOn: $model.state.room.adjustLevel)
                    Toggle("Line up the timing (nearer speakers play slightly later)", isOn: $model.state.room.adjustDelay)
                }
                .disabled(!room.compensate)
                .opacity(room.compensate ? 1 : 0.5)

                Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 6) {
                    GridRow {
                        Text("Speaker")
                        Text("Distance from you").gridColumnAlignment(.trailing)
                        Text("Volume change").gridColumnAlignment(.trailing)
                        Text("Added delay").gridColumnAlignment(.trailing)
                    }
                    .font(.caption).foregroundStyle(Theme.dim)
                    ForEach(Speaker.allCases) { speaker in
                        let adjustment = adjustments[speaker.rawValue]
                        GridRow {
                            Text(speaker.name)
                            Text(String(format: "%.2f m", adjustment.distanceM)).monospacedDigit()
                            Text(room.compensate ? String(format: "%.1f dB", adjustment.trimDb) : "none")
                                .monospacedDigit()
                                .foregroundStyle(adjustment.trimDb < -0.05 ? Theme.amber : Theme.dim)
                            Text(room.compensate ? String(format: "%.1f ms", adjustment.delayMs) : "none")
                                .monospacedDigit()
                                .foregroundStyle(adjustment.delayMs > 0.05 ? Theme.amber : Theme.dim)
                        }
                    }
                }
                Hint("Drag the amber “You” marker in the room picture to your seat. The farthest speaker is left alone and the nearer ones are turned down (about 6 dB each time the distance halves, 15 dB at most) and delayed (sound travels 343 metres a second), so everything reaches you equally loud and at the same moment. These changes are added to your own volume and delay settings. Turn the master volume up if the result is too quiet.")
            }

            Card(title: "Saved spots") {
                if room.spots.isEmpty {
                    Hint("No spots yet. Drag “You” to a place you listen from, name it below and save it.")
                }
                ForEach(room.spots) { spot in
                    HStack {
                        ChoiceButton(title: spot.name, isSelected: model.currentSpot == spot, tint: Theme.amber) {
                            model.goToSpot(spot)
                        }
                        .frame(width: 180)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            model.state.room.spots.removeAll { $0.name == spot.name }
                        }
                        .accessibilityLabel("Remove \(spot.name)")
                    }
                }
                HStack {
                    TextField("Name, for example Desk or Bed", text: $newSpotName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(saveSpot)
                    Button("Save current position", action: saveSpot)
                        .disabled(newSpotName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Hint("Saved spots also appear in the menu bar icon's menu, so you can switch without opening this window.")
            }

            Card(title: "Your room") {
                HStack(spacing: 18) {
                    HStack(spacing: 8) {
                        Text("Width (TV wall)")
                        ValueField(value: $model.state.room.widthM, range: 1.5...15, decimals: 2, unit: "m", label: "Room width in metres")
                    }
                    HStack(spacing: 8) {
                        Text("Depth")
                        ValueField(value: $model.state.room.depthM, range: 1.5...15, decimals: 2, unit: "m", label: "Room depth in metres")
                    }
                    Spacer()
                }
                HStack {
                    Toggle("Arrange speakers", isOn: $model.isArrangingSpeakers)
                        .toggleStyle(.switch)
                    Spacer()
                    Button("Reset speaker positions") { model.state.room.speakers = RoomState.defaultSpeakers }
                }
                Hint(model.isArrangingSpeakers
                     ? "Now drag each speaker in the room picture to where it really is. The grid squares are one metre. Turn this off when you are done."
                     : "Measure your room, enter its size, then turn on Arrange speakers to drag each speaker to its real place. The more accurate the picture, the better the adjustment.")
            }
        }
        .onDisappear { model.isArrangingSpeakers = false }
    }

    private func saveSpot() {
        model.saveSpot(named: newSpotName)
        newSpotName = ""
    }
}
