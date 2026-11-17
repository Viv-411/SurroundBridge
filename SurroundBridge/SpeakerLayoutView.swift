//
//  SpeakerLayoutView.swift
//  SurroundBridge
//
//  A top-down picture of the room, drawn to scale. Click a speaker to select it, drag the amber
//  marker to where you sit, and (in "arrange" mode) drag speakers to where they really are.
//
//  Performance note: while something is being dragged, its position lives in this view's own
//  @State, so only this picture redraws. The app's settings (and with them the audio engine and
//  every other screen) are only updated a few times a second for "You", and on release.
//

import SwiftUI

struct SpeakerLayoutView: View {
    @Environment(BridgeModel.self) private var model

    @State private var draggedSpeaker: Int? = nil
    @State private var draggedSpeakerPoint: Point2? = nil
    @State private var draggedListener: Point2? = nil
    @State private var lastListenerCommit = Date.distantPast

    private func clamped(_ point: CGPoint, in size: CGSize) -> Point2 {
        Point2(x: min(max(Double(point.x / size.width), 0.05), 0.95),
               y: min(max(Double(point.y / size.height), 0.05), 0.95))
    }

    /// The room as it should be drawn right now: the saved one, plus whatever is being dragged.
    private var liveRoom: RoomState {
        var room = model.state.room
        if let index = draggedSpeaker, let point = draggedSpeakerPoint { room.speakers[index] = point }
        if let point = draggedListener { room.listener = point }
        return room
    }

    var body: some View {
        let room = liveRoom
        let shape = min(max(room.widthM / room.depthM, 0.7), 1.5)

        GeometryReader { geo in
            let size = geo.size
            let me = CGPoint(x: size.width * room.listener.x, y: size.height * room.listener.y)
            let adjustments = room.adjustments()
            let panel = Theme.panel, line = Theme.line, amber = Theme.amber

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(panel)

                Canvas { context, size in
                    // floor grid: one square per metre, so distances can be judged by eye
                    var grid = Path()
                    for metre in stride(from: 1.0, to: room.widthM, by: 1.0) {
                        let x = size.width * metre / room.widthM
                        grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for metre in stride(from: 1.0, to: room.depthM, by: 1.0) {
                        let y = size.height * metre / room.depthM
                        grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(grid, with: .color(line.opacity(0.55)), lineWidth: 0.5)

                    // when adjusting for position: a line from you to every speaker, with its length
                    guard room.compensate else { return }
                    for speaker in Speaker.allCases {
                        let spot = room.speakers[speaker.rawValue]
                        let point = CGPoint(x: size.width * spot.x, y: size.height * spot.y)
                        var ray = Path()
                        ray.move(to: me); ray.addLine(to: point)
                        context.stroke(ray, with: .color(amber.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        let middle = CGPoint(x: (me.x + point.x) / 2, y: (me.y + point.y) / 2)
                        let label = Text(String(format: "%.1f m", adjustments[speaker.rawValue].distanceM))
                            .font(.system(size: 10, weight: .medium)).foregroundStyle(amber)
                        let resolved = context.resolve(label)
                        let textSize = resolved.measure(in: size)
                        let box = CGRect(x: middle.x - textSize.width / 2 - 3, y: middle.y - textSize.height / 2 - 1,
                                         width: textSize.width + 6, height: textSize.height + 2)
                        context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(panel))
                        context.draw(resolved, at: middle)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))

                // the TV wall
                Capsule().fill(Theme.dim)
                    .frame(width: size.width * 0.3, height: 5)
                    .position(x: size.width * 0.5, y: 9)

                Text(String(format: "%.1f × %.1f m", room.widthM, room.depthM))
                    .font(.caption2).foregroundStyle(Theme.dim)
                    .position(x: size.width - 44, y: size.height - 12)

                ForEach(Speaker.allCases) { speaker in
                    let spot = room.speakers[speaker.rawValue]
                    SpeakerNode(speaker: speaker, isBeingDragged: draggedSpeaker == speaker.rawValue)
                        .position(x: size.width * spot.x, y: size.height * spot.y)
                        .gesture(speakerGesture(for: speaker, in: size))
                }

                ListenerMarker(isActive: room.compensate)
                    .position(me)
                    .gesture(listenerGesture(in: size))
            }
            .coordinateSpace(name: "room")
        }
        .aspectRatio(shape, contentMode: .fit)
    }

    /// A click selects the speaker. In arrange mode, a drag moves it.
    private func speakerGesture(for speaker: Speaker, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("room"))
            .onChanged { drag in
                guard model.isArrangingSpeakers else { return }
                let moved = abs(drag.translation.width) + abs(drag.translation.height) > 3
                if moved || draggedSpeaker != nil {
                    draggedSpeaker = speaker.rawValue
                    draggedSpeakerPoint = clamped(drag.location, in: size)
                }
            }
            .onEnded { _ in
                if let index = draggedSpeaker, let point = draggedSpeakerPoint {
                    model.state.room.speakers[index] = point
                }
                draggedSpeaker = nil
                draggedSpeakerPoint = nil
                if model.selected != speaker { model.selected = speaker }
            }
    }

    private func listenerGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("room"))
            .onChanged { drag in
                let point = clamped(drag.location, in: size)
                draggedListener = point
                // let the sound follow while dragging, but only a few times a second
                if Date().timeIntervalSince(lastListenerCommit) > 0.15 {
                    lastListenerCommit = Date()
                    model.state.room.listener = point
                }
            }
            .onEnded { drag in
                model.state.room.listener = clamped(drag.location, in: size)
                draggedListener = nil
            }
    }
}

/// "You": drag it to your seat.
private struct ListenerMarker: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().fill(Theme.amber.opacity(isActive ? 0.25 : 0)).frame(width: 46, height: 46)
                Circle().fill(isActive ? Theme.amber : Theme.raised).frame(width: 30, height: 30)
                Circle().strokeBorder(Theme.amber, lineWidth: 1.5).frame(width: 30, height: 30)
                Image(systemName: "person.fill").font(.footnote)
                    .foregroundStyle(isActive ? Theme.onSignal : Theme.amber)
            }
            Text("You").font(.caption2.weight(.semibold)).foregroundStyle(Theme.amber)
        }
        .contentShape(Rectangle())
        .help("Drag to where you sit")
        .accessibilityLabel("Your position")
        .accessibilityHint("Drag to where you sit")
    }
}

private struct SpeakerNode: View {
    @Environment(BridgeModel.self) private var model
    let speaker: Speaker
    let isBeingDragged: Bool

    var body: some View {
        let channel = model.state.channels[speaker.rawValue]
        let anySolo = model.state.channels.contains { $0.solo }
        let silent = channel.mute || (anySolo && !channel.solo)
        let isSelected = model.selected == speaker
        let isTesting = model.toneSpeaker == speaker
        let glow = isTesting ? Theme.amber : Theme.signal

        ZStack {
            SpeakerHalo(speaker: speaker, color: glow)
            Circle().fill(isSelected ? glow : Theme.raised).frame(width: 44, height: 44)
            Circle().strokeBorder(silent ? Theme.alert.opacity(0.8) : glow.opacity(isSelected ? 0 : 0.7),
                                  style: StrokeStyle(lineWidth: 1.5, dash: model.isArrangingSpeakers ? [4, 3] : []))
                .frame(width: 44, height: 44)
            VStack(spacing: 0) {
                Image(systemName: silent ? "speaker.slash.fill" : (speaker == .sub ? "hifispeaker.fill" : "speaker.wave.2.fill"))
                    .font(.system(size: 10))
                Text(speaker.short).font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(isSelected ? Theme.onSignal : (silent ? Theme.dim : Theme.text))
        }
        .frame(width: 80, height: 80)
        .scaleEffect(isBeingDragged ? 1.12 : 1)
        .contentShape(Circle())
        .help(model.isArrangingSpeakers ? "Drag \(speaker.name) to where it is in your room" : speaker.name)
        .accessibilityElement()
        .accessibilityLabel(speaker.name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { model.selected = speaker }
    }
}

/// The live level halo. A separate view so that 30 meter updates a second redraw only this circle.
private struct SpeakerHalo: View {
    @Environment(MeterModel.self) private var meters
    let speaker: Speaker
    let color: Color

    var body: some View {
        let level = meters.output[speaker.rawValue]
        Circle().fill(color.opacity(0.22))
            .frame(width: 44 + 36 * level, height: 44 + 36 * level)
    }
}
