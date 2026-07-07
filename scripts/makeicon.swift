// Renders the Sleight app icon (a knob/dial on a deep gradient squircle)
// at all required sizes. Run: swift scripts/makeicon.swift
// Then: iconutil -c icns assets/AppIcon.iconset -o assets/AppIcon.icns

import AppKit
import CoreGraphics

func drawIcon(size: Int, to url: URL) {
    let s = CGFloat(size)
    guard let context = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }

    // macOS-style squircle with the standard transparent margin.
    let inset = s * 0.085
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let squircle = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.addPath(squircle)
    context.clip()

    // Background: deep indigo -> violet vertical gradient.
    let colors = [
        CGColor(red: 0.13, green: 0.12, blue: 0.28, alpha: 1),
        CGColor(red: 0.35, green: 0.20, blue: 0.65, alpha: 1),
    ] as CFArray
    let gradient = CGGradient(colorsSpace: nil, colors: colors, locations: [0, 1])!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: s / 2, y: rect.minY),
        end: CGPoint(x: s / 2, y: rect.maxY),
        options: []
    )

    let center = CGPoint(x: s / 2, y: s / 2)
    let dialRadius = rect.width * 0.30

    // Tick marks around the dial.
    context.setStrokeColor(CGColor(gray: 1.0, alpha: 0.35))
    context.setLineCap(.round)
    let tickCount = 24
    for i in 0..<tickCount {
        let angle = CGFloat(i) / CGFloat(tickCount) * 2 * .pi
        let inner = dialRadius * 1.22
        let outer = dialRadius * (i % 6 == 0 ? 1.40 : 1.32)
        context.setLineWidth(s * (i % 6 == 0 ? 0.016 : 0.009))
        context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        context.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
        context.strokePath()
    }

    // Knob body with subtle radial shading.
    let knobColors = [
        CGColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1),
        CGColor(red: 0.80, green: 0.80, blue: 0.92, alpha: 1),
    ] as CFArray
    let knobGradient = CGGradient(colorsSpace: nil, colors: knobColors, locations: [0, 1])!
    context.saveGState()
    context.addEllipse(in: CGRect(
        x: center.x - dialRadius, y: center.y - dialRadius,
        width: dialRadius * 2, height: dialRadius * 2
    ))
    context.clip()
    context.drawRadialGradient(
        knobGradient,
        startCenter: CGPoint(x: center.x - dialRadius * 0.3, y: center.y + dialRadius * 0.4),
        startRadius: 0,
        endCenter: center,
        endRadius: dialRadius * 1.4,
        options: []
    )
    context.restoreGState()

    // Indicator line pointing to 2 o'clock.
    let angle: CGFloat = .pi / 4
    context.setStrokeColor(CGColor(red: 0.35, green: 0.20, blue: 0.65, alpha: 1))
    context.setLineWidth(s * 0.035)
    context.setLineCap(.round)
    context.move(to: CGPoint(
        x: center.x + cos(angle) * dialRadius * 0.35,
        y: center.y + sin(angle) * dialRadius * 0.35
    ))
    context.addLine(to: CGPoint(
        x: center.x + cos(angle) * dialRadius * 0.82,
        y: center.y + sin(angle) * dialRadius * 0.82
    ))
    context.strokePath()

    let image = context.makeImage()!
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: size, height: size)
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: url)
}

let iconsetURL = URL(fileURLWithPath: "assets/AppIcon.iconset")
try! FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let entries: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in entries {
    drawIcon(size: size, to: iconsetURL.appendingPathComponent(name))
}
print("iconset written")
