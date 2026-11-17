//
//  SettingsTab.swift
//  SurroundBridge
//
//  Appearance and information about the app.
//

import SwiftUI

struct SettingsTab: View {
    @Environment(BridgeModel.self) private var model

    var body: some View {
        let store = ThemeStore.shared
        VStack(spacing: 12) {
            Card(title: "Appearance") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                    ForEach(AppTheme.allCases) { theme in
                        ThemeSwatch(theme: theme, isSelected: store.theme == theme) { store.theme = theme }
                    }
                }
                Hint(store.theme.summary)
            }

            Card(title: "About") {
                let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                Text("SurroundBridge \(version)").font(.title3.weight(.semibold))
                Text("Made by Vivek Bharadwaj.")
                Text("Built on SoundPusher by Daniel Vollmer (MIT License), which provides the virtual 5.1 device, the audio capture and the real-time Dolby Digital encoding. Also uses FFmpeg and TPCircularBuffer.")
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 16) {
                    Link("SurroundBridge on GitHub", destination: URL(string: "https://github.com/Viv-411/SurroundBridge")!)
                    Link("SoundPusher", destination: URL(string: "https://codeberg.org/q-p/SoundPusher")!)
                }
            }
        }
    }
}

/// A small preview of a theme that you click to choose it.
private struct ThemeSwatch: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        let colors = theme.palette
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 7).fill(colors.chassis)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 5) {
                            Circle().fill(colors.signal).frame(width: 10, height: 10)
                            Circle().fill(colors.amber).frame(width: 10, height: 10)
                            Circle().fill(colors.alert).frame(width: 10, height: 10)
                        }
                        RoundedRectangle(cornerRadius: 4).fill(colors.panel).frame(height: 22)
                            .overlay(alignment: .leading) {
                                Capsule().fill(colors.signal).frame(width: 46, height: 4).padding(.leading, 7)
                            }
                    }
                    .padding(8)
                }
                .frame(height: 62)
                .environment(\.colorScheme, colors.colorScheme ?? .light)
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.line))

                HStack {
                    Text(theme.name).fontWeight(isSelected ? .semibold : .regular)
                    Spacer()
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.signal) }
                }
            }
            .padding(8)
            .background(Theme.raised.opacity(isSelected ? 1 : 0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(isSelected ? Theme.signal : .clear, lineWidth: 2))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.name) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
