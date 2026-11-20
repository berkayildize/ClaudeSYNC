#!/usr/bin/env swift
import AppKit
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate-icon.swift <output-iconset-dir>\n", stderr)
    exit(1)
}

let iconsetURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let specs: [(String, Int)] = [
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

func drawStarburst(in cg: CGContext, center: CGPoint, outerRadius: CGFloat, color: CGColor) {
    cg.saveGState()
    cg.setFillColor(color)

    let rayCount = 10
    let innerHub = outerRadius * 0.24
    cg.fillEllipse(in: CGRect(
        x: center.x - innerHub,
        y: center.y - innerHub,
        width: innerHub * 2,
        height: innerHub * 2
    ))

    for i in 0..<rayCount {
        let angle = (CGFloat(i) / CGFloat(rayCount)) * (.pi * 2.0) + (.pi / 20.0)
        let isPrimary = (i % 2 == 0)
        let length = outerRadius * (isPrimary ? 1.0 : 0.82)
        let halfBase = outerRadius * (isPrimary ? 0.105 : 0.088)
        let halfTip = outerRadius * (isPrimary ? 0.068 : 0.055)

        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: angle)

        let p = CGMutablePath()
        p.move(to: CGPoint(x: innerHub * 0.55, y: -halfBase))
        p.addLine(to: CGPoint(x: length - halfTip, y: -halfTip))
        p.addArc(
            center: CGPoint(x: length - halfTip, y: 0),
            radius: halfTip,
            startAngle: -.pi / 2,
            endAngle: .pi / 2,
            clockwise: false
        )
        p.addLine(to: CGPoint(x: innerHub * 0.55, y: halfBase))
        p.closeSubpath()

        cg.addPath(p)
        cg.fillPath()
        cg.restoreGState()
    }
    cg.restoreGState()
}

func drawTransferArrows(in cg: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, lineWidth: CGFloat) {
    cg.saveGState()
    cg.setStrokeColor(color)
    cg.setLineWidth(lineWidth)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)

    let dx = radius * 0.54
    let dy = radius * 0.26
    let head = radius * 0.24

    // Top arrow →
    let topY = center.y + dy
    cg.move(to: CGPoint(x: center.x - dx, y: topY))
    cg.addLine(to: CGPoint(x: center.x + dx, y: topY))
    cg.move(to: CGPoint(x: center.x + dx - head, y: topY + head))
    cg.addLine(to: CGPoint(x: center.x + dx, y: topY))
    cg.addLine(to: CGPoint(x: center.x + dx - head, y: topY - head))

    // Bottom arrow ←
    let botY = center.y - dy
    cg.move(to: CGPoint(x: center.x + dx, y: botY))
    cg.addLine(to: CGPoint(x: center.x - dx, y: botY))
    cg.move(to: CGPoint(x: center.x - dx + head, y: botY + head))
    cg.addLine(to: CGPoint(x: center.x - dx, y: botY))
    cg.addLine(to: CGPoint(x: center.x - dx + head, y: botY - head))

    cg.strokePath()
    cg.restoreGState()
}

func renderIcon(size: Int) -> Data? {
    let s = CGFloat(size)
    guard let rep = NSBitmapImageRep(
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
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext

    let inset = s * 0.08
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = rect.width * 0.225
    let tilePath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

    let tileBg = NSColor(calibratedRed: 0.11, green: 0.12, blue: 0.145, alpha: 1.0)
    let terracotta = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)

    // Flat matte obsidian macOS icon tile (zero gradients)
    cg.saveGState()
    cg.addPath(tilePath)
    cg.clip()
    cg.setFillColor(tileBg.cgColor)
    cg.fill(rect)
    cg.restoreGState()

    // Crisp Apple hairline rim
    cg.addPath(tilePath)
    cg.setStrokeColor(NSColor.white.withAlphaComponent(0.18).cgColor)
    cg.setLineWidth(max(1.0, s * 0.014))
    cg.strokePath()

    // Claude starburst centered slightly upper-left
    let starCenter = CGPoint(x: s * 0.455, y: s * 0.545)
    let starRadius = rect.width * 0.335
    drawStarburst(in: cg, center: starCenter, outerRadius: starRadius, color: terracotta.cgColor)

    // Crisp lower-right circular sync badge with dark cutout ring
    let badgeRadius = rect.width * 0.185
    let badgeCenter = CGPoint(x: rect.maxX - badgeRadius - rect.width * 0.105, y: rect.minY + badgeRadius + rect.width * 0.105)
    let cutoutRadius = badgeRadius + rect.width * 0.038

    cg.setFillColor(tileBg.cgColor)
    cg.fillEllipse(in: CGRect(
        x: badgeCenter.x - cutoutRadius,
        y: badgeCenter.y - cutoutRadius,
        width: cutoutRadius * 2,
        height: cutoutRadius * 2
    ))

    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(
        x: badgeCenter.x - badgeRadius,
        y: badgeCenter.y - badgeRadius,
        width: badgeRadius * 2,
        height: badgeRadius * 2
    ))

    drawTransferArrows(
        in: cg,
        center: badgeCenter,
        radius: badgeRadius * 0.88,
        color: tileBg.cgColor,
        lineWidth: max(1.0, badgeRadius * 0.21)
    )

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for (filename, size) in specs {
    if let png = renderIcon(size: size) {
        try png.write(to: iconsetURL.appendingPathComponent(filename))
    }
}
