//
//  SpeakerLayoutView.swift
//  SurroundBridge
//
//  A top-down picture of the room, drawn to scale. Click a speaker to select it, drag the amber
//  marker to where you sit, and (in "arrange" mode) drag speakers to where they really are.
//

import SwiftUI

struct SpeakerLayoutView: View {
    @Environment(BridgeModel.self) private var model

    private func clamped(_ point: CGPoint, in size: CGSize) -> Point2 {
        Point2(x: min(max(Double(point.x / size.width), 0.05), 0.95),
               y: min(max(Double(point.y / size.height), 0.05), 0.95))
    }

    var body: some View {
        let room = model.state.room
        let shape = min(max(room.widthM / room.depthM, 0.7), 1.5)

        GeometryReader { geo in
            let size = geo.size
            let me = CGPoint(x: size.width * room.listener.x, y: size.height * room.listener.y)
            let adjustments = room.adjustments()

            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(Theme.panel)

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
                    context.stroke(grid, with: .color(Theme.line.opacity(0.55)), lineWidth: 0.5)

                    // when adjusting for position: a line from you to every speaker, with its length
                    guard room.compensate else { return }
                    for speaker in Speaker.allCases {
                        let spot = room.speakers[speaker.rawValue]
                        let point = CGPoint(x: size.width * spot.x, y: size.height * spot.y)
                        var line = Path()
                        line.move(to: me); line.addLine(to: point)
                        context.stroke(line, with: .color(Theme.amber.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        let middle = CGPoint(x: (me.x + point.x) / 2, y: (me.y + point.y) / 2)
                        let label = Text(String(format: "%.1f m", adjustments[speaker.rawValue].distanceM))
                            .font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(Theme.amber)
                        let resolved = context.resolve(label)
                        let textSize = resolved.measure(in: size)
                        let box = CGRect(x: middle.x - textSize.width / 2 - 3, y: middle.y - textSize.height / 2 - 1,
                                         width: textSize.width + 6, height: textSize.height + 2)
                        context.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(Theme.panel))
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
                    SpeakerNode(speaker: speaker)
                        .position(x: size.width * spot.x, y: size.height * spot.y)
                        .gesture(
                            DragGesture(minimumDistance: 2, coordinateSpace: .named("room")).onChanged { drag in
                                model.state.room.speakers[speaker.rawValue] = clamped(drag.location, in: size)
                            },
                            including: model.isArrangingSpeakers ? .all : .subviews)
                }

                ListenerMarker(isActive: room.compensate)
                    .position(me)
                    .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("room")).onChanged { drag in
                        model.state.room.listener = clamped(drag.location, in: size)
                    })
            }
            .coordinateSpace(name: "room")
        }
        .aspectRatio(shape, contentMode: .fit)
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
                    .foregroundStyle(isActive ? Theme.chassis : Theme.amber)
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
    @Environment(MeterModel.self) private var meters
    let speaker: Speaker

    var body: some View {
        let channel = model.state.channels[speaker.rawValue]
        let anySolo = model.state.channels.contains { $0.solo }
        let silent = channel.mute || (anySolo && !channel.solo)
        let isSelected = model.selected == speaker
        let isTesting = model.toneSpeaker == speaker
        let level = meters.output[speaker.rawValue]
        let glow = isTesting ? Theme.amber : Theme.signal

        Button {
            model.selected = speaker
        } label: {
            ZStack {
                // live level: a soft halo that grows with the signal
                Circle().fill(glow.opacity(0.22))
                    .frame(width: 44 + 36 * level, height: 44 + 36 * level)
                Circle().fill(isSelected ? glow : Theme.raised).frame(width: 44, height: 44)
                Circle().strokeBorder(silent ? Theme.alert.opacity(0.8) : glow.opacity(isSelected ? 0 : 0.7),
                                      style: StrokeStyle(lineWidth: 1.5, dash: model.isArrangingSpeakers ? [4, 3] : []))
                    .frame(width: 44, height: 44)
                VStack(spacing: 0) {
                    Image(systemName: silent ? "speaker.slash.fill" : (speaker == .sub ? "hifispeaker.fill" : "speaker.wave.2.fill"))
                        .font(.system(size: 10))
                    Text(speaker.short).font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .foregroundStyle(isSelected ? Theme.chassis : (silent ? Theme.dim : Theme.text))
            }
            .frame(width: 80, height: 80)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(model.isArrangingSpeakers ? "Drag \(speaker.name) to where it is in your room" : speaker.name)
        .accessibilityLabel(speaker.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
