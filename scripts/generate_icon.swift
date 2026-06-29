#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let rootURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let assetsURL = rootURL.appendingPathComponent("assets", isDirectory: true)
let buildURL = rootURL.appendingPathComponent(".build/icon", isDirectory: true)
let iconsetURL = buildURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icnsURL = assetsURL.appendingPathComponent("AppIcon.icns")
let previewURL = assetsURL.appendingPathComponent("AppIcon.png")

try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    let red = CGFloat((hex >> 16) & 0xff) / 255
    let green = CGFloat((hex >> 8) & 0xff) / 255
    let blue = CGFloat(hex & 0xff) / 255
    return NSColor(calibratedRed: red, green: green, blue: blue, alpha: alpha)
}

func scaled(_ value: CGFloat, _ scale: CGFloat) -> CGFloat {
    value * scale
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ scale: CGFloat) -> NSRect {
    NSRect(x: scaled(x, scale), y: scaled(y, scale), width: scaled(width, scale), height: scaled(height, scale))
}

func oval(_ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ scale: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: rect(x, y, size, size, scale))
}

func drawWindow(
    in windowRect: NSRect,
    cornerRadius: CGFloat,
    fill: NSColor,
    titleBar: NSColor,
    stroke: NSColor,
    dotAlpha: CGFloat,
    scale: CGFloat
) {
    let path = NSBezierPath(roundedRect: windowRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let shadow = NSShadow()
    shadow.shadowColor = color(0x020617, alpha: 0.32)
    shadow.shadowBlurRadius = scaled(22, scale)
    shadow.shadowOffset = NSSize(width: 0, height: scaled(-16, scale))

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    fill.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    path.addClip()
    let titleRect = NSRect(
        x: windowRect.minX,
        y: windowRect.maxY - scaled(68, scale),
        width: windowRect.width,
        height: scaled(68, scale)
    )
    titleBar.setFill()
    titleRect.fill()
    NSGraphicsContext.restoreGraphicsState()

    stroke.setStroke()
    path.lineWidth = scaled(2, scale)
    path.stroke()

    let dotY = windowRect.maxY - scaled(41, scale)
    let dotSize = scaled(20, scale)
    let firstDotX = windowRect.minX + scaled(44, scale)
    [color(0xfb7185, alpha: dotAlpha), color(0xfbbf24, alpha: dotAlpha), color(0x34d399, alpha: dotAlpha)]
        .enumerated()
        .forEach { index, dotColor in
            dotColor.setFill()
            NSBezierPath(ovalIn: NSRect(
                x: firstDotX + CGFloat(index) * scaled(36, scale),
                y: dotY - dotSize / 2,
                width: dotSize,
                height: dotSize
            )).fill()
        }
}

func drawPill(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, scale: CGFloat, alpha: CGFloat) {
    let pill = NSBezierPath(roundedRect: rect(x, y, width, height, scale), xRadius: scaled(height / 2, scale), yRadius: scaled(height / 2, scale))
    color(0x64748b, alpha: alpha).setFill()
    pill.fill()
}

func pngData(size pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "AltpIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap"])
    }

    bitmap.size = NSSize(width: pixels, height: pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "AltpIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create graphics context"])
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)
    context.cgContext.setAllowsAntialiasing(true)

    let scale = CGFloat(pixels) / 1024
    let canvas = NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
    context.cgContext.clear(canvas)

    let baseRect = rect(64, 64, 896, 896, scale)
    let basePath = NSBezierPath(roundedRect: baseRect, xRadius: scaled(212, scale), yRadius: scaled(212, scale))
    let baseShadow = NSShadow()
    baseShadow.shadowColor = color(0x020617, alpha: 0.35)
    baseShadow.shadowBlurRadius = scaled(48, scale)
    baseShadow.shadowOffset = NSSize(width: 0, height: scaled(-20, scale))

    NSGraphicsContext.saveGraphicsState()
    baseShadow.set()
    let baseGradient = NSGradient(colors: [color(0x172033), color(0x164c6e), color(0x0f9f95)])!
    baseGradient.draw(in: basePath, angle: 315)
    NSGraphicsContext.restoreGraphicsState()

    let shine = NSBezierPath()
    shine.move(to: NSPoint(x: scaled(156, scale), y: scaled(859, scale)))
    shine.curve(
        to: NSPoint(x: scaled(869, scale), y: scaled(838, scale)),
        controlPoint1: NSPoint(x: scaled(219, scale), y: scaled(913, scale)),
        controlPoint2: NSPoint(x: scaled(802, scale), y: scaled(922, scale))
    )
    color(0xffffff, alpha: 0.18).setStroke()
    shine.lineWidth = scaled(24, scale)
    shine.lineCapStyle = .round
    shine.stroke()

    drawWindow(
        in: rect(274, 526, 478, 260, scale),
        cornerRadius: scaled(38, scale),
        fill: color(0xe0f2fe, alpha: 0.43),
        titleBar: color(0x0f172a, alpha: 0.16),
        stroke: color(0xffffff, alpha: 0.08),
        dotAlpha: 0,
        scale: scale
    )

    drawWindow(
        in: rect(212, 406, 548, 288, scale),
        cornerRadius: scaled(42, scale),
        fill: color(0xecfeff, alpha: 0.72),
        titleBar: color(0x0f172a, alpha: 0.13),
        stroke: color(0xffffff, alpha: 0.14),
        dotAlpha: 0.95,
        scale: scale
    )

    let frontRect = rect(286, 322, 502, 304, scale)
    drawWindow(
        in: frontRect,
        cornerRadius: scaled(46, scale),
        fill: color(0xf8fafc),
        titleBar: color(0xd7e2f0),
        stroke: color(0xffffff, alpha: 0.55),
        dotAlpha: 1,
        scale: scale
    )

    drawPill(x: 340, y: 472, width: 392, height: 34, scale: scale, alpha: 0.45)
    drawPill(x: 340, y: 410, width: 268, height: 28, scale: scale, alpha: 0.32)

    let lensShadow = NSShadow()
    lensShadow.shadowColor = color(0x020617, alpha: 0.36)
    lensShadow.shadowBlurRadius = scaled(26, scale)
    lensShadow.shadowOffset = NSSize(width: 0, height: scaled(-14, scale))

    NSGraphicsContext.saveGraphicsState()
    lensShadow.set()
    let lens = NSBezierPath(ovalIn: rect(266, 269, 278, 278, scale))
    lens.lineWidth = scaled(54, scale)
    color(0x67e8f9).setStroke()
    lens.stroke()

    let lensAccent = NSBezierPath(ovalIn: rect(266, 269, 278, 278, scale))
    lensAccent.lineWidth = scaled(30, scale)
    color(0x5eead4, alpha: 0.95).setStroke()
    lensAccent.stroke()

    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: scaled(512, scale), y: scaled(298, scale)))
    handle.line(to: NSPoint(x: scaled(634, scale), y: scaled(176, scale)))
    handle.lineWidth = scaled(62, scale)
    handle.lineCapStyle = .round
    color(0x67e8f9).setStroke()
    handle.stroke()

    let handleAccent = NSBezierPath()
    handleAccent.move(to: NSPoint(x: scaled(512, scale), y: scaled(298, scale)))
    handleAccent.line(to: NSPoint(x: scaled(634, scale), y: scaled(176, scale)))
    handleAccent.lineWidth = scaled(34, scale)
    handleAccent.lineCapStyle = .round
    color(0x5eead4, alpha: 0.95).setStroke()
    handleAccent.stroke()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AltpIcon", code: 3, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    return data
}

let iconFiles: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, pixels) in iconFiles {
    try pngData(size: pixels).write(to: iconsetURL.appendingPathComponent(name))
}
try pngData(size: 1024).write(to: previewURL)

try? fileManager.removeItem(at: icnsURL)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", "-o", icnsURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    throw NSError(domain: "AltpIcon", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
}

print("Generated \(icnsURL.path)")
print("Generated \(previewURL.path)")
