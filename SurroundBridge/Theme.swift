//
//  Theme.swift
//  SurroundBridge
//
//  The app's colours. There are several themes to choose from (Settings tab); views never use
//  fixed colours, they ask `Theme` for a role such as "panel" or "signal".
//

import AppKit
import SwiftUI

/// One set of colours, by role.
struct ThemePalette {
    var chassis: Color      // window background
    var panel: Color        // cards
    var raised: Color       // controls sitting on a card
    var line: Color         // hairlines and grids
    var signal: Color       // live audio, selection
    var amber: Color        // the listener, test signals, solo
    var alert: Color        // mute, clipping
    var text: Color
    var dim: Color          // secondary text
    var onSignal: Color     // text drawn on top of `signal` / `amber` / `alert`
    var colorScheme: ColorScheme?   // nil = follow the Mac's light / dark setting
    var rounded = false     // rounded lettering
}

private func hex(_ value: UInt32) -> Color {
    Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, graphite, daylight, midnight, aurora

    var id: String { rawValue }

    var name: String {
        switch self {
        case .system: "macOS"
        case .graphite: "Graphite"
        case .daylight: "Daylight"
        case .midnight: "Midnight"
        case .aurora: "Aurora"
        }
    }

    var summary: String {
        switch self {
        case .system: "Standard Mac look. Follows light or dark mode and your accent colour."
        case .graphite: "Neutral dark grey with blue."
        case .daylight: "Bright and clean."
        case .midnight: "Deep navy with teal, like a receiver display."
        case .aurora: "Dark violet with soft purple."
        }
    }

    var palette: ThemePalette {
        switch self {
        case .system:
            ThemePalette(chassis: Color(nsColor: .windowBackgroundColor), panel: Color.primary.opacity(0.055),
                         raised: Color.primary.opacity(0.1), line: Color(nsColor: .separatorColor),
                         signal: .accentColor, amber: .orange, alert: .red, text: .primary, dim: .secondary,
                         onSignal: .white, colorScheme: nil)
        case .graphite:
            ThemePalette(chassis: hex(0x1B1B1D), panel: hex(0x27272A), raised: hex(0x38383C), line: hex(0x4A4A50),
                         signal: hex(0x6AA9FF), amber: hex(0xFFB340), alert: hex(0xFF6B62), text: hex(0xF2F2F4), dim: hex(0xA3A3AB),
                         onSignal: hex(0x101114), colorScheme: .dark)
        case .daylight:
            ThemePalette(chassis: hex(0xF1F3F6), panel: hex(0xFFFFFF), raised: hex(0xE4E8EE), line: hex(0xCDD3DC),
                         signal: hex(0x0B7285), amber: hex(0xD9730D), alert: hex(0xD92D20), text: hex(0x17202B), dim: hex(0x566273),
                         onSignal: hex(0xFFFFFF), colorScheme: .light)
        case .midnight:
            ThemePalette(chassis: hex(0x161C28), panel: hex(0x202939), raised: hex(0x2C374B), line: hex(0x3B4861),
                         signal: hex(0x57D9C9), amber: hex(0xF4B740), alert: hex(0xFF6B5E), text: hex(0xE9EEF5), dim: hex(0x97A4B8),
                         onSignal: hex(0x161C28), colorScheme: .dark, rounded: true)
        case .aurora:
            ThemePalette(chassis: hex(0x17131F), panel: hex(0x231C30), raised: hex(0x342A47), line: hex(0x473A60),
                         signal: hex(0xB89AFF), amber: hex(0xFFC857), alert: hex(0xFF7A85), text: hex(0xF0ECF8), dim: hex(0xA79FBA),
                         onSignal: hex(0x17131F), colorScheme: .dark, rounded: true)
        }
    }
}

/// Remembers which theme is chosen. Views that read `Theme.…` redraw automatically when it changes.
@Observable
final class ThemeStore {
    static let shared = ThemeStore()
    private static let key = "Theme"

    var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: Self.key)
            AppController.shared.applyWindowTheme()
        }
    }

    private init() {
        theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: Self.key) ?? "") ?? .system
    }
}

/// Shorthand for the colours of the current theme.
enum Theme {
    static var current: ThemePalette { ThemeStore.shared.theme.palette }
    static var chassis: Color { current.chassis }
    static var panel: Color { current.panel }
    static var raised: Color { current.raised }
    static var line: Color { current.line }
    static var signal: Color { current.signal }
    static var amber: Color { current.amber }
    static var alert: Color { current.alert }
    static var text: Color { current.text }
    static var dim: Color { current.dim }
    static var onSignal: Color { current.onSignal }
}

/// The SurroundBridge mark: a listener surrounded by five speakers. Also used for the app and menu bar icons.
struct SurroundGlyph: View {
    var body: some View {
        let signal = Theme.signal, amber = Theme.amber
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
            let radius = min(size.width, size.height) * 0.36
            let dot = min(size.width, size.height) * 0.085
            for degrees in [-90.0, -42, -138, 28, 152] {
                let angle = degrees * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(signal))
            }
            let me = dot * 1.25
            context.fill(Path(ellipseIn: CGRect(x: center.x - me, y: center.y - me, width: me * 2, height: me * 2)),
                         with: .color(amber))
        }
        .accessibilityHidden(true)
    }
}
