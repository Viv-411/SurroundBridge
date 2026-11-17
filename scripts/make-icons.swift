// Draws SurroundBridge's app icon (all sizes) and its two menu bar icons.
// The mark is a listener (amber) surrounded by five speakers (teal), seen from above.
// Usage: swift scripts/make-icons.swift   (run from the repository root)
import AppKit
import CoreGraphics
import Foundation

let assets = URL(fileURLWithPath: "SoundPusher/Assets.xcassets")
/// Angles of the five speakers around the listener (degrees, 0 = right, -90 = straight ahead).
let speakerAngles: [Double] = [-90, -42, -138, 28, 152]

func rgb(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let teal = (0.341, 0.851, 0.788), amber = (0.957, 0.718, 0.251)

func drawAppIcon(_ ctx: CGContext, size s: CGFloat) {
    // macOS icons are a rounded square that leaves a margin around the edge
    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03, color: rgb(0, 0, 0, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(rgb(0.09, 0.11, 0.16)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [
        rgb(0.165, 0.216, 0.318), rgb(0.070, 0.090, 0.135)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.midX, y: tile.maxY), end: CGPoint(x: tile.midX, y: tile.minY), options: [])

    // CoreGraphics has y pointing up, so "ahead of the listener" is +y here
    let center = CGPoint(x: tile.midX, y: tile.midY - tile.height * 0.045)
    let radius = tile.width * 0.335

    // sound rings spreading from the listener
    for (fraction, alpha) in [(0.42, 0.34), (0.7, 0.22), (1.0, 0.13)] {
        ctx.setStrokeColor(rgb(teal.0, teal.1, teal.2, alpha))
        ctx.setLineWidth(max(s * 0.012, 0.5))
        ctx.strokeEllipse(in: CGRect(x: center.x - radius * fraction, y: center.y - radius * fraction,
                                     width: radius * 2 * fraction, height: radius * 2 * fraction))
    }
    let dot = tile.width * 0.062
    for degrees in speakerAngles {
        let angle = -degrees * .pi / 180
        let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        ctx.setShadow(offset: .zero, blur: s * 0.035, color: rgb(teal.0, teal.1, teal.2, 0.8))
        ctx.setFillColor(rgb(teal.0, teal.1, teal.2))
        ctx.fillEllipse(in: CGRect(x: p.x - dot, y: p.y - dot, width: dot * 2, height: dot * 2))
    }
    let me = tile.width * 0.082
    ctx.setShadow(offset: .zero, blur: s * 0.04, color: rgb(amber.0, amber.1, amber.2, 0.75))
    ctx.setFillColor(rgb(amber.0, amber.1, amber.2))
    ctx.fillEllipse(in: CGRect(x: center.x - me, y: center.y - me, width: me * 2, height: me * 2))
    ctx.restoreGState()
}

func writePNG(pixels: Int, to url: URL) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    drawAppIcon(ctx, size: CGFloat(pixels))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// Menu bar icons are "templates": only the shape matters, macOS colours them to suit the menu bar.
func writeMenuBarPDF(connected: Bool, to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 19, height: 19)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    let center = CGPoint(x: 9.5, y: 8.7)
    let radius = 6.6
    ctx.setFillColor(rgb(0, 0, 0)); ctx.setStrokeColor(rgb(0, 0, 0)); ctx.setLineWidth(1.1)
    for degrees in speakerAngles {
        let angle = -degrees * .pi / 180
        let p = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        let r = CGRect(x: p.x - 1.75, y: p.y - 1.75, width: 3.5, height: 3.5)
        if connected { ctx.fillEllipse(in: r) } else { ctx.strokeEllipse(in: r.insetBy(dx: 0.55, dy: 0.55)) }
    }
    let m = CGRect(x: center.x - 2.4, y: center.y - 2.4, width: 4.8, height: 4.8)
    if connected { ctx.fillEllipse(in: m) } else { ctx.strokeEllipse(in: m.insetBy(dx: 0.55, dy: 0.55)) }
    ctx.endPDFPage()
    ctx.closePDF()
}

let icon = assets.appendingPathComponent("AppIcon.appiconset")
for (name, pixels) in [("16x16", 16), ("16x16@2", 32), ("32x32", 32), ("32x32@2", 64), ("128x128", 128),
                       ("128x128@2", 256), ("256x256", 256), ("256x256@2", 512), ("512x512", 512), ("512x512@2", 1024)] {
    writePNG(pixels: pixels, to: icon.appendingPathComponent("speaker_\(name).png"))
}
// (the image sets keep SoundPusher's names because its code refers to them: Cable = connected, CableCut = not connected)
writeMenuBarPDF(connected: true, to: assets.appendingPathComponent("CableTemplate.imageset/CableTemplate.pdf"))
writeMenuBarPDF(connected: false, to: assets.appendingPathComponent("CableCutTemplate.imageset/CableCutTemplate.pdf"))
print("icons written")
