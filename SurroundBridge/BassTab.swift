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
        VStack(spacing: 12) {
            Card(title: "Bass management") {
                Toggle("Send low frequencies from the speakers to the subwoofer", isOn: $model.state.bassEnabled)
                Group {
                    LabeledSlider(title: "Crossover", value: $model.state.crossoverHz, range: 40...200, unit: "Hz", decimals: 0)
                    LabeledSlider(title: "Moved bass level", value: $model.state.bassRedirectDb, range: -20...0)
                    HStack(spacing: 8) {
                        Text("Take bass from").frame(width: 120, alignment: .leading)
                        ForEach(Speaker.allCases.filter { $0 != .sub }) { speaker in
                            ChoiceButton(title: speaker.short, isSelected: model.state.bassFrom[speaker.rawValue]) {
                                model.state.bassFrom[speaker.rawValue].toggle()
                            }
                            .frame(width: 54)
                            .help(speaker.name)
                        }
                    }
                }
                .disabled(!model.state.bassEnabled)
                .opacity(model.state.bassEnabled ? 1 : 0.5)
                Hint("Sounds below the crossover are removed from the chosen speakers and played by the subwoofer instead, so small speakers don't have to struggle with bass. Stereo sources such as music have no subwoofer channel of their own, so this is what gives the subwoofer a real signal. The default level of −10 dB matches how Dolby Digital decoders boost the subwoofer channel by 10 dB. Dolby Digital limits that channel to about 120 Hz, so 80 to 120 Hz is a good range.")
            }

            Card(title: "Safety limiter") {
                Toggle("Stop the output from clipping", isOn: $model.state.limiterEnabled)
                Group {
                    LabeledSlider(title: "Ceiling", value: $model.state.limiterCeilingDb, range: -12...0)
                    LabeledSlider(title: "Release", value: $model.state.limiterReleaseMs, range: 20...500, unit: "ms", decimals: 0)
                    HStack(spacing: 10) {
                        Text("Turning down").frame(width: 120, alignment: .leading)
                        LevelMeter(level: min(meters.limiterReductionDb / 12, 1))
                        Text(meters.limiterReductionDb < 0.05 ? "0.0 dB" : String(format: "−%.1f dB", meters.limiterReductionDb))
                            .monospacedDigit().foregroundStyle(Theme.dim)
                            .frame(width: 76, alignment: .trailing)
                    }
                }
                .disabled(!model.state.limiterEnabled)
                .opacity(model.state.limiterEnabled ? 1 : 0.5)
                Hint("Boosting volume or EQ, or mixing several channels into one speaker, can push the signal past the loudest level digital audio can carry, which sounds harsh. The limiter briefly turns everything down just enough to prevent that. If the meter moves a lot, lower the master volume a little.")
            }

            Card(title: "Source levels") {
                ForEach(Speaker.allCases) { source in
                    HStack(spacing: 10) {
                        Text(source.name).frame(width: 120, alignment: .leading)
                        LevelMeter(level: meters.input[source.rawValue])
                    }
                }
                Hint("What the Mac is sending before any processing. If only Front Left and Front Right move, the app that is playing sends stereo.")
            }
        }
    }
}
