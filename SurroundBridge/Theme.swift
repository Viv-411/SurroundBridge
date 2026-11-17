//
//  Theme.swift
//  SurroundBridge
//
//  The app's look, in one place. Inspired by the display of a hi-fi receiver:
//  deep navy "chassis", teal for live signal, amber for you and for tests.
//

import SwiftUI

enum Theme {
    static let chassis = Color(red: 0.086, green: 0.110, blue: 0.157)   // window background
    static let panel = Color(red: 0.125, green: 0.161, blue: 0.224)     // cards
    static let raised = Color(red: 0.173, green: 0.216, blue: 0.294)    // controls sitting on a card
    static let line = Color(red: 0.231, green: 0.282, blue: 0.380)      // hairlines and grids
    static let signal = Color(red: 0.341, green: 0.851, blue: 0.788)    // live audio, selection
    static let amber = Color(red: 0.957, green: 0.718, blue: 0.251)     // the listener, test signals, solo
    static let alert = Color(red: 1.0, green: 0.42, blue: 0.369)        // mute, clipping
    static let text = Color(red: 0.914, green: 0.933, blue: 0.961)
    static let dim = Color(red: 0.592, green: 0.643, blue: 0.722)       // secondary text
}

/// The SurroundBridge mark: a listener surrounded by five speakers. Also used for the app and menu bar icons.
struct SurroundGlyph: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height * 0.56)
            let radius = min(size.width, size.height) * 0.36
            let dot = min(size.width, size.height) * 0.085
            for degrees in [-90.0, -42, -138, 28, 152] {
                let angle = degrees * .pi / 180
                let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                context.fill(Path(ellipseIn: CGRect(x: point.x - dot, y: point.y - dot, width: dot * 2, height: dot * 2)),
                             with: .color(Theme.signal))
            }
            let me = dot * 1.25
            context.fill(Path(ellipseIn: CGRect(x: center.x - me, y: center.y - me, width: me * 2, height: me * 2)),
                         with: .color(Theme.amber))
        }
        .accessibilityHidden(true)
    }
}
