#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

// Usage: swift generate-dmg-bg.swift <out_1x.png> <out_2x.png> [version]
guard CommandLine.arguments.count >= 3 else {
    fputs("Usage: generate-dmg-bg.swift <out_1x.png> <out_2x.png> [version]\n", stderr)
    exit(1)
}

let out1x = URL(fileURLWithPath: CommandLine.arguments[1])
let out2x = URL(fileURLWithPath: CommandLine.arguments[2])
let versionStr = CommandLine.arguments.count >= 4 ? CommandLine.arguments[3] : "0.0.5"

// Exact Finder DMG window content dimensions (points)
let W: CGFloat = 660
let H: CGFloat = 420

// Flat Editorial Matte Obsidian Palette (Zero Gradients)
enum C {
    static let bg = NSColor(calibratedRed: 0.055, green: 0.062, blue: 0.080, alpha: 1.0)         // #0E1014
    static let card = NSColor(calibratedRed: 0.088, green: 0.096, blue: 0.120, alpha: 1.0)       // #16181F
    static let cardElevated = NSColor(calibratedRed: 0.112, green: 0.122, blue: 0.150, alpha: 1.0)
    static let hairline = NSColor(calibratedWhite: 1.0, alpha: 0.11)
    static let hairlineSoft = NSColor(calibratedWhite: 1.0, alpha: 0.075)
    static let terracotta = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)    // #D97757
    static let textPrimary = NSColor(calibratedWhite: 0.96, alpha: 1.0)
    static let textSecondary = NSColor(calibratedRed: 0.59, green: 0.62, blue: 0.68, alpha: 1.0)
    static let textTertiary = NSColor(calibratedRed: 0.43, green: 0.46, blue: 0.52, alpha: 1.0)
}

func fillRounded(_ cg: CGContext, rect: CGRect, r: CGFloat, fill: NSColor, stroke: NSColor? = nil, lw: CGFloat = 1.0, dashed: Bool = false) {
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.setFillColor(fill.cgColor)
    cg.fillPath()
    if let stroke {
        cg.addPath(path)
        cg.setStrokeColor(stroke.cgColor)
        cg.setLineWidth(lw)
        if dashed {
            cg.setLineDash(phase: 0, lengths: [5, 4])
        }
        cg.strokePath()
    }
    cg.restoreGState()
}

func drawText(_ s: String, in rect: CGRect, font: NSFont, color: NSColor, align: NSTextAlignment = .left, kern: CGFloat = 0) {
    let p = NSMutableParagraphStyle()
    p.alignment = align
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: p
    ]
    if kern != 0 { attrs[.kern] = kern }
    NSAttributedString(string: s, attributes: attrs).draw(in: rect)
}

func drawStarburst(_ cg: CGContext, center: CGPoint, outerRadius: CGFloat, color: CGColor) {
    cg.saveGState()
    cg.setFillColor(color)
    let rayCount = 10
    let hub = outerRadius * 0.24
    cg.fillEllipse(in: CGRect(x: center.x - hub, y: center.y - hub, width: hub * 2, height: hub * 2))
    for i in 0..<rayCount {
        let angle = (CGFloat(i) / CGFloat(rayCount)) * (.pi * 2.0) + (.pi / 20.0)
        let primary = (i % 2 == 0)
        let len = outerRadius * (primary ? 1.0 : 0.82)
        let hb = outerRadius * (primary ? 0.105 : 0.088)
        let ht = outerRadius * (primary ? 0.068 : 0.055)
        cg.saveGState()
        cg.translateBy(x: center.x, y: center.y)
        cg.rotate(by: angle)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: hub * 0.55, y: -hb))
        p.addLine(to: CGPoint(x: len - ht, y: -ht))
        p.addArc(center: CGPoint(x: len - ht, y: 0), radius: ht, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
        p.addLine(to: CGPoint(x: hub * 0.55, y: hb))
        p.closeSubpath()
        cg.addPath(p)
        cg.fillPath()
        cg.restoreGState()
    }
    cg.restoreGState()
}

func drawTransferArrows(_ cg: CGContext, center: CGPoint, radius: CGFloat, color: CGColor, lineWidth: CGFloat) {
    cg.saveGState()
    cg.setStrokeColor(color)
    cg.setLineWidth(lineWidth)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    let dx = radius * 0.54
    let dy = radius * 0.26
    let head = radius * 0.24

    let topY = center.y + dy
    cg.move(to: CGPoint(x: center.x - dx, y: topY))
    cg.addLine(to: CGPoint(x: center.x + dx, y: topY))
    cg.move(to: CGPoint(x: center.x + dx - head, y: topY + head))
    cg.addLine(to: CGPoint(x: center.x + dx, y: topY))
    cg.addLine(to: CGPoint(x: center.x + dx - head, y: topY - head))

    let botY = center.y - dy
    cg.move(to: CGPoint(x: center.x + dx, y: botY))
    cg.addLine(to: CGPoint(x: center.x - dx, y: botY))
    cg.move(to: CGPoint(x: center.x - dx + head, y: botY + head))
    cg.addLine(to: CGPoint(x: center.x - dx, y: botY))
    cg.addLine(to: CGPoint(x: center.x - dx + head, y: botY - head))
    cg.strokePath()
    cg.restoreGState()
}

func drawMiniIcon(_ cg: CGContext, rect: CGRect) {
    let tileBg = NSColor(calibratedRed: 0.115, green: 0.125, blue: 0.15, alpha: 1.0)
    fillRounded(cg, rect: rect, r: rect.width * 0.24, fill: tileBg, stroke: NSColor.white.withAlphaComponent(0.18), lw: 0.9)
    let starCenter = CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.56)
    drawStarburst(cg, center: starCenter, outerRadius: rect.width * 0.34, color: C.terracotta.cgColor)

    let badgeR = rect.width * 0.19
    let badgeCenter = CGPoint(x: rect.maxX - badgeR - rect.width * 0.11, y: rect.minY + badgeR + rect.height * 0.11)
    let cutR = badgeR + rect.width * 0.036
    cg.setFillColor(tileBg.cgColor)
    cg.fillEllipse(in: CGRect(x: badgeCenter.x - cutR, y: badgeCenter.y - cutR, width: cutR * 2, height: cutR * 2))
    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR, width: badgeR * 2, height: badgeR * 2))
    drawTransferArrows(cg, center: badgeCenter, radius: badgeR * 0.88, color: tileBg.cgColor, lineWidth: max(0.8, badgeR * 0.22))
}

func render(scale: CGFloat) -> NSBitmapImageRep {
    let pixW = Int(W * scale)
    let pixH = Int(H * scale)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixW,
        pixelsHigh: pixH,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: W, height: H) // Sets exact DPI (72 for 1x, 144 for 2x)

    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.setShouldSmoothFonts(true)

    // Note: Standard AppKit/CG bottom-left origin (y=0 at bottom, y=420 at top)
    // Helper to convert top-down y + height into CG bottom-left rect
    func topRect(x: CGFloat, topY: CGFloat, w: CGFloat, h: CGFloat) -> CGRect {
        CGRect(x: x, y: H - topY - h, width: w, height: h)
    }

    // 1. Matte Obsidian Backdrop + Subtle Architectural Dot Grid
    cg.setFillColor(C.bg.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: W, height: H))

    cg.saveGState()
    cg.setFillColor(NSColor.white.withAlphaComponent(0.04).cgColor)
    var gx: CGFloat = 18
    while gx < W {
        var gy: CGFloat = 18
        while gy < H {
            cg.fillEllipse(in: CGRect(x: gx - 0.65, y: gy - 0.65, width: 1.3, height: 1.3))
            gy += 24
        }
        gx += 24
    }
    cg.restoreGState()

    // 2. Top Centered Brand Row
    let brandW: CGFloat = 216
    let brandX = (W - brandW) / 2
    drawMiniIcon(cg, rect: topRect(x: brandX, topY: 26, w: 26, h: 26))
    drawText(
        "ClaudeSYNC",
        in: topRect(x: brandX + 34, topY: 26, w: 124, h: 26),
        font: .systemFont(ofSize: 19, weight: .bold),
        color: C.textPrimary,
        kern: -0.4
    )
    let verRect = topRect(x: brandX + 158, topY: 30, w: 54, h: 19)
    fillRounded(cg, rect: verRect, r: 9.5, fill: C.cardElevated, stroke: C.hairline, lw: 0.8)
    drawText(
        "v\(versionStr)",
        in: topRect(x: brandX + 158, topY: 32.5, w: 54, h: 15),
        font: .monospacedSystemFont(ofSize: 10, weight: .semibold),
        color: C.terracotta,
        align: .center
    )

    // Bilingual crisp install instruction
    drawText(
        "Drag ClaudeSYNC to Applications  ·  Uygulamayı Applications klasörüne sürükleyin",
        in: topRect(x: 40, topY: 63, w: W - 80, h: 20),
        font: .systemFont(ofSize: 11.5, weight: .medium),
        color: C.textSecondary,
        align: .center
    )

    // 3. Center Symmetric Dual Drop-Zone Cards
    // Finder icon centers: Left = (180, 206), Right = (480, 206) in Finder top-down coordinates
    let cardW: CGFloat = 212
    let cardH: CGFloat = 216
    let cardTopY: CGFloat = 108
    let leftCenterX: CGFloat = 180
    let rightCenterX: CGFloat = 480

    let leftCard = topRect(x: leftCenterX - cardW / 2, topY: cardTopY, w: cardW, h: cardH)
    let rightCard = topRect(x: rightCenterX - cardW / 2, topY: cardTopY, w: cardW, h: cardH)

    fillRounded(cg, rect: leftCard, r: 18, fill: C.card, stroke: C.hairline, lw: 1.0)
    fillRounded(cg, rect: rightCard, r: 18, fill: C.card, stroke: C.terracotta.withAlphaComponent(0.48), lw: 1.15, dashed: true)

    // Subtle top tags inside both cards (clean breathing room above the 108pt Finder icons)
    drawText(
        "APPLICATION",
        in: topRect(x: leftCenterX - 90, topY: cardTopY + 14, w: 180, h: 14),
        font: .systemFont(ofSize: 8.5, weight: .bold),
        color: C.textTertiary,
        align: .center,
        kern: 1.1
    )
    drawText(
        "DROP HERE · BURAYA BIRAKIN",
        in: topRect(x: rightCenterX - 96, topY: cardTopY + 14, w: 192, h: 14),
        font: .systemFont(ofSize: 8.5, weight: .bold),
        color: C.terracotta,
        align: .center,
        kern: 1.0
    )

    // 4. Center Transfer Arrow Connector between Cards
    let midX = W / 2
    let midY = H - (cardTopY + cardH / 2)

    cg.saveGState()
    cg.setStrokeColor(C.hairline.cgColor)
    cg.setLineWidth(1.2)
    cg.move(to: CGPoint(x: leftCard.maxX + 6, y: midY))
    cg.addLine(to: CGPoint(x: midX - 25, y: midY))
    cg.move(to: CGPoint(x: midX + 25, y: midY))
    cg.addLine(to: CGPoint(x: rightCard.minX - 6, y: midY))
    cg.strokePath()
    cg.restoreGState()

    let arrowBadge = CGRect(x: midX - 21, y: midY - 21, width: 42, height: 42)
    fillRounded(cg, rect: arrowBadge, r: 21, fill: C.cardElevated, stroke: C.terracotta.withAlphaComponent(0.65), lw: 1.2)

    // Crisp vector right arrow inside circle
    cg.saveGState()
    cg.setStrokeColor(C.terracotta.cgColor)
    cg.setLineWidth(2.1)
    cg.setLineCap(.round)
    cg.setLineJoin(.round)
    cg.move(to: CGPoint(x: midX - 8, y: midY))
    cg.addLine(to: CGPoint(x: midX + 8, y: midY))
    cg.move(to: CGPoint(x: midX + 2.5, y: midY + 5.5))
    cg.addLine(to: CGPoint(x: midX + 8, y: midY))
    cg.addLine(to: CGPoint(x: midX + 2.5, y: midY - 5.5))
    cg.strokePath()
    cg.restoreGState()

    // 5. Bottom Symmetric Architectural Footer Pill
    let footerW: CGFloat = 512
    let footerRect = topRect(x: (W - footerW) / 2, topY: 356, w: footerW, h: 34)
    fillRounded(cg, rect: footerRect, r: 10, fill: C.card, stroke: C.hairlineSoft, lw: 0.9)

    let specs = [
        "100% Local · Zero Network",
        "Native SwiftUI · macOS 14+",
        "English & Türkçe · MIT"
    ]
    let stepW = footerW / CGFloat(specs.count)
    for (i, label) in specs.enumerated() {
        let sx = footerRect.minX + CGFloat(i) * stepW
        drawText(
            label,
            in: topRect(x: sx + 4, topY: 365.5, w: stepW - 8, h: 16),
            font: .systemFont(ofSize: 10.5, weight: .medium),
            color: C.textSecondary,
            align: .center
        )
        if i < specs.count - 1 {
            cg.setFillColor(C.hairlineSoft.cgColor)
            cg.fill(CGRect(x: sx + stepW, y: footerRect.minY + 9, width: 1, height: footerRect.height - 18))
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func writePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    try data.write(to: url)
}

try writePNG(render(scale: 1.0), to: out1x)
try writePNG(render(scale: 2.0), to: out2x)
print("Generated DMG background 1x + 2x (v\(versionStr))")
