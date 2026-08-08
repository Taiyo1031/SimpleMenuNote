#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <AppIcon.appiconset>\n", stderr)
    exit(2)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let outputs: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

func renderIcon(size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let inset = CGFloat(size) * 0.055
    let backgroundRect = canvas.insetBy(dx: inset, dy: inset)
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: CGFloat(size) * 0.22,
        yRadius: CGFloat(size) * 0.22
    )
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.98, alpha: 1),
            NSColor(calibratedRed: 0.31, green: 0.32, blue: 0.91, alpha: 1)
        ]
    )!
    gradient.draw(in: backgroundPath, angle: -55)

    let pageRect = NSRect(
        x: CGFloat(size) * 0.25,
        y: CGFloat(size) * 0.19,
        width: CGFloat(size) * 0.50,
        height: CGFloat(size) * 0.63
    )
    let pagePath = NSBezierPath(
        roundedRect: pageRect,
        xRadius: CGFloat(size) * 0.045,
        yRadius: CGFloat(size) * 0.045
    )
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
    shadow.shadowBlurRadius = CGFloat(size) * 0.035
    shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(size) * 0.02)
    shadow.set()
    NSColor.white.setFill()
    pagePath.fill()
    NSGraphicsContext.current?.saveGraphicsState()
    NSShadow().set()

    let lineColor = NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.72, alpha: 0.9)
    lineColor.setStroke()
    let lineWidth = max(1.25, CGFloat(size) * 0.022)
    for (index, widthFactor) in [0.34, 0.40, 0.31].enumerated() {
        let y = CGFloat(size) * (0.63 - CGFloat(index) * 0.13)
        let line = NSBezierPath()
        line.lineWidth = lineWidth
        line.lineCapStyle = .round
        line.move(to: NSPoint(x: CGFloat(size) * 0.33, y: y))
        line.line(to: NSPoint(x: CGFloat(size) * (0.33 + widthFactor), y: y))
        line.stroke()
    }

    let hashPath = NSBezierPath()
    hashPath.lineWidth = max(1, CGFloat(size) * 0.015)
    hashPath.lineCapStyle = .round
    let hashX = CGFloat(size) * 0.34
    let hashY = CGFloat(size) * 0.715
    let hashSize = CGFloat(size) * 0.075
    for offset in [CGFloat(0.025), CGFloat(0.055)] {
        hashPath.move(to: NSPoint(x: hashX + offset * CGFloat(size), y: hashY))
        hashPath.line(to: NSPoint(x: hashX + offset * CGFloat(size) - hashSize * 0.2, y: hashY + hashSize))
    }
    for offset in [CGFloat(0.025), CGFloat(0.055)] {
        hashPath.move(to: NSPoint(x: hashX, y: hashY + offset * CGFloat(size)))
        hashPath.line(to: NSPoint(x: hashX + hashSize, y: hashY + offset * CGFloat(size)))
    }
    hashPath.stroke()

    NSGraphicsContext.current?.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "SimpleMenuNoteIcon", code: 1)
    }
    return data
}

for (filename, size) in outputs {
    try renderIcon(size: size).write(to: outputDirectory.appendingPathComponent(filename))
}
