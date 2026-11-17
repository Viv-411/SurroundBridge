//
//  SpeakerLayoutView.swift
//  SurroundBridge
//
//  A top-down picture of the room. Click a speaker to select it; the rings pulse with its live level.
//

import SwiftUI

struct SpeakerLayoutView: View {
    @Environment(BridgeModel.self) private var model

    /// Where each speaker sits in the room picture (0...1 across, 0...1 down).
    private func position(_ speaker: Speaker) -> CGPoint {
        switch speaker {
        case .frontLeft: CGPoint(x: 0.17, y: 0.2)
        case .center: CGPoint(x: 0.5, y: 0.16)
        case .frontRight: CGPoint(x: 0.83, y: 0.2)
        case .sub: CGPoint(x: 0.14, y: 0.48)
        case .surroundLeft: CGPoint(x: 0.17, y: 0.84)
        case .surroundRight: CGPoint(x: 0.83, y: 0.84)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                RoundedRectangle(cornerRadius: 14).fill(.background.secondary)
                RoundedRectangle(cornerRadius: 14).strokeBorder(.separator)

                // the TV
                RoundedRectangle(cornerRadius: 3)
                    .fill(.secondary)
                    .frame(width: size.width * 0.34, height: 7)
                    .position(x: size.width * 0.5, y: size.height * 0.055)

                // the listener
                VStack(spacing: 2) {
                    Image(systemName: "sofa.fill").font(.title)
                    Text("You").font(.caption2)
                }
                .foregroundStyle(.tertiary)
                .position(x: size.width * 0.5, y: size.height * 0.6)

                ForEach(Speaker.allCases) { speaker in
                    SpeakerNode(speaker: speaker)
                        .position(x: size.width * position(speaker).x, y: size.height * position(speaker).y)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
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

        Button {
            model.selected = speaker
        } label: {
            ZStack {
                // live level: a soft ring that grows with the signal
                Circle()
                    .fill((isTesting ? Color.orange : Color.green).opacity(0.28))
                    .frame(width: 50 + 34 * level, height: 50 + 34 * level)
                Circle()
                    .fill(silent ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.background))
                    .frame(width: 50, height: 50)
                Circle()
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.5), lineWidth: isSelected ? 3 : 1)
                    .frame(width: 50, height: 50)
                VStack(spacing: 1) {
                    Image(systemName: silent ? "speaker.slash.fill" : (speaker == .sub ? "hifispeaker.fill" : "speaker.wave.2.fill"))
                        .font(.footnote)
                    Text(speaker.short).font(.caption2.bold())
                }
                .foregroundStyle(silent ? .secondary : .primary)
            }
            .frame(width: 88, height: 88)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(speaker.name)
        .accessibilityLabel(speaker.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
