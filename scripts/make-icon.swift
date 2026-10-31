#!/usr/bin/env swift
// Renders the app icon into Sources/Assets.xcassets/AppIcon.appiconset.
// Usage: swift scripts/make-icon.swift
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Sources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext

    // macOS icon grid: 824/1024 body with ~22% corner radius.
    let inset = s * 100 / 1024
    let body = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = body.width * 0.225
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(bodyPath)
    ctx.setFillColor(NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1).cgColor)
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(srgbRed: 0.18, green: 0.83, blue: 0.75, alpha: 1).cgColor,
            NSColor(srgbRed: 0.04, green: 0.46, blue: 0.43, alpha: 1).cgColor,
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: [])

    // The edge panel: a white card hugging the right side.
    let card = CGRect(x: body.minX + body.width * 0.30, y: body.minY + body.height * 0.16,
                      width: body.width * 0.56, height: body.height * 0.68)
    let cardPath = CGPath(roundedRect: card, cornerWidth: card.width * 0.14, cornerHeight: card.width * 0.14, transform: nil)
    ctx.setShadow(offset: CGSize(width: -s * 0.012, height: -s * 0.006), blur: s * 0.04, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    ctx.addPath(cardPath)
    ctx.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
    ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)

    // Three rows: a checked todo, an open todo, a tip line.
    let teal = NSColor(srgbRed: 0.05, green: 0.58, blue: 0.53, alpha: 1).cgColor
    let grey = NSColor(srgbRed: 0.75, green: 0.78, blue: 0.80, alpha: 1).cgColor
    let rowX = card.minX + card.width * 0.14
    let dot = card.width * 0.17
    let lineH = card.height * 0.055
    for (i, y) in [0.72, 0.47, 0.22].enumerated() {
        let cy = card.minY + card.height * y
        let circle = CGRect(x: rowX, y: cy - dot / 2, width: dot, height: dot)
        if i == 0 {
            ctx.setFillColor(teal)
            ctx.fillEllipse(in: circle)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(dot * 0.16)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.move(to: CGPoint(x: circle.minX + dot * 0.27, y: circle.midY))
            ctx.addLine(to: CGPoint(x: circle.minX + dot * 0.44, y: circle.minY + dot * 0.32))
            ctx.addLine(to: CGPoint(x: circle.minX + dot * 0.74, y: circle.minY + dot * 0.68))
            ctx.strokePath()
        } else if i == 1 {
            ctx.setStrokeColor(teal)
            ctx.setLineWidth(dot * 0.13)
            ctx.strokeEllipse(in: circle.insetBy(dx: dot * 0.07, dy: dot * 0.07))
        } else {
            ctx.setFillColor(NSColor(srgbRed: 0.90, green: 0.28, blue: 0.30, alpha: 1).cgColor)
            let tri = CGMutablePath()
            tri.move(to: CGPoint(x: circle.minX + dot * 0.1, y: circle.minY + dot * 0.2))
            tri.addLine(to: CGPoint(x: circle.maxX - dot * 0.1, y: circle.minY + dot * 0.2))
            tri.addLine(to: CGPoint(x: circle.midX, y: circle.maxY - dot * 0.15))
            tri.closeSubpath()
            ctx.addPath(tri)
            ctx.fillPath()
        }
        let lineX = rowX + dot * 1.45
        let width = (card.maxX - card.width * 0.12 - lineX) * (i == 1 ? 0.75 : 1)
        let line = CGRect(x: lineX, y: cy - lineH / 2, width: width, height: lineH)
        ctx.addPath(CGPath(roundedRect: line, cornerWidth: lineH / 2, cornerHeight: lineH / 2, transform: nil))
        ctx.setFillColor(i == 0 ? NSColor(srgbRed: 0.85, green: 0.87, blue: 0.88, alpha: 1).cgColor : grey)
        ctx.fillPath()
    }
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = points * scale
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try render(size: pixels).write(to: output.appendingPathComponent(name))
        images.append(["idiom": "mac", "size": "\(points)x\(points)", "scale": "\(scale)x", "filename": name])
    }
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: output.appendingPathComponent("Contents.json"))

let catalog = output.deletingLastPathComponent().appendingPathComponent("Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!.write(to: catalog)
print("Wrote icon to \(output.path)")
