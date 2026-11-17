//
//  BassTab.swift
//  SurroundBridge
//
//  Bass management (crossover to the subwoofer) and the safety limiter.
//

import SwiftUI

struct BassTab: View {
    @Environment(BridgeModel.self) private var model
    @Environment(MeterModel.self) private var meters

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 14) {
            Card(title: "Bass Management") {
                Toggle("Send low frequencies from the speakers to the subwoofer", isOn: $model.state.bassEnabled)
                Group {
                    LabeledSlider(title: "Crossover", value: $model.state.crossoverHz, range: 40...200, step: 5) { formatHz($0) }
                    LabeledSlider(title: "Moved bass level", value: $model.state.bassRedirectDb, range: -20...0, step: 0.5, format: formatDb)
                    HStack(spacing: 10) {
                        Text("Take bass from").frame(width: 110, alignment: .leading)
                        ForEach(Speaker.allCases.filter { $0 != .sub }) { speaker in
                            Toggle(speaker.short, isOn: $model.state.bassFrom[speaker.rawValue])
                                .toggleStyle(.button)
                                .help(speaker.name)
                        }
                    }
                }
                .disabled(!model.state.bassEnabled)
                Text("Sounds below the crossover are removed from the chosen speakers and played by the subwoofer instead, so small speakers don't have to struggle with bass. Stereo sources such as music have no subwoofer channel of their own, so this is what gives the subwoofer a real signal. The default level of −10 dB matches how Dolby Digital decoders boost the subwoofer channel by 10 dB. Dolby Digital limits the subwoofer channel to about 120 Hz, and your Sony may already do its own bass management, so 80–120 Hz is a good range.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "Safety Limiter") {
                Toggle("Stop the output from clipping", isOn: $model.state.limiterEnabled)
                Group {
                    LabeledSlider(title: "Ceiling", value: $model.state.limiterCeilingDb, range: -12...0, step: 0.5, format: formatDb)
                    LabeledSlider(title: "Release", value: $model.state.limiterReleaseMs, range: 20...500, step: 10) { String(format: "%.0f ms", $0) }
                    HStack(spacing: 10) {
                        Text("Turning down").frame(width: 110, alignment: .leading)
                        LevelMeter(level: min(meters.limiterReductionDb / 12, 1))
                        Text(meters.limiterReductionDb < 0.05 ? "0.0 dB" : String(format: "−%.1f dB", meters.limiterReductionDb))
                            .monospacedDigit().foregroundStyle(.secondary)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                .disabled(!model.state.limiterEnabled)
                Text("Boosting volume or EQ, or mixing several channels into one speaker, can push the signal past the loudest level digital audio can carry, which sounds harsh. The limiter briefly turns everything down just enough to prevent that. If the meter moves a lot, lower the master volume a little.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(title: "Source Levels") {
                ForEach(Speaker.allCases) { source in
                    HStack(spacing: 10) {
                        Text(source.name).frame(width: 110, alignment: .leading)
                        LevelMeter(level: meters.input[source.rawValue])
                    }
                }
                Text("What the Mac is sending before any processing. If only Front Left and Front Right move, the app playing is sending stereo.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
