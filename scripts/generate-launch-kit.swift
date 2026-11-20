#!/usr/bin/env swift
import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

// MARK: - Paths

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let assetsURL = rootURL.appendingPathComponent("docs/assets", isDirectory: true)
let visualsOutURL = rootURL.appendingPathComponent("launch-kit/visuals", isDirectory: true)
let videoOutURL = rootURL.appendingPathComponent("launch-kit/video", isDirectory: true)
let keyframesOutURL = videoOutURL.appendingPathComponent("keyframes", isDirectory: true)

try FileManager.default.createDirectory(at: visualsOutURL, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: keyframesOutURL, withIntermediateDirectories: true)

// MARK: - Flat Editorial Palette (Zero Gradients)

enum Palette {
    static let canvasBg = NSColor(calibratedRed: 0.047, green: 0.051, blue: 0.063, alpha: 1.0) // #0C0D10
    static let cardBg = NSColor(calibratedRed: 0.082, green: 0.088, blue: 0.106, alpha: 1.0)   // #15161B
    static let cardElevated = NSColor(calibratedRed: 0.106, green: 0.114, blue: 0.137, alpha: 1.0)
    static let lightBg = NSColor(calibratedRed: 0.945, green: 0.953, blue: 0.968, alpha: 1.0)
    static let hairlineDark = NSColor(calibratedWhite: 1.0, alpha: 0.11)
    static let hairlineStrong = NSColor(calibratedWhite: 1.0, alpha: 0.17)
    static let textPrimary = NSColor(calibratedWhite: 0.96, alpha: 1.0)
    static let textSecondary = NSColor(calibratedRed: 0.60, green: 0.62, blue: 0.67, alpha: 1.0)
    static let textTertiary = NSColor(calibratedRed: 0.42, green: 0.44, blue: 0.50, alpha: 1.0)
    static let terracotta = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)  // #D97757
    static let appleBlue = NSColor(calibratedRed: 0.16, green: 0.52, blue: 0.98, alpha: 1.0)
    static let appleGreen = NSColor(calibratedRed: 0.20, green: 0.80, blue: 0.45, alpha: 1.0)
    static let appleRed = NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.35, alpha: 1.0)
    static let appleOrange = NSColor(calibratedRed: 0.96, green: 0.63, blue: 0.16, alpha: 1.0)
}

// MARK: - Load Crisp Retina Assets

func loadCGImage(_ name: String) -> CGImage {
    let url = assetsURL.appendingPathComponent(name)
    guard let img = NSImage(contentsOf: url),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Missing asset: \(url.path)")
    }
    return cg
}

let imgMainDark = loadCGImage("app-main-dark.png")
let imgLimitsDark = loadCGImage("app-limits-dark.png")
let imgProfilesDark = loadCGImage("app-profiles-dark.png")
let imgSettingsDark = loadCGImage("app-settings-dark.png")
let imgMainLight = loadCGImage("app-main-light.png")
let imgMenuBarPopover = loadCGImage("menubar-popover-dark.png")
let imgMenuBarBars = loadCGImage("menubar-bars.png")

/// Crops the outer studio margin (28pt = 56px @2x) cleanly off our captured window screenshots.
func cropWindowOnly(_ img: CGImage, padPx: Int = 56) -> CGImage {
    let rect = CGRect(
        x: padPx,
        y: padPx,
        width: max(1, img.width - padPx * 2),
        height: max(1, img.height - padPx * 2)
    )
    return img.cropping(to: rect) ?? img
}

let winMainDark = cropWindowOnly(imgMainDark)
let winLimitsDark = cropWindowOnly(imgLimitsDark)
let winProfilesDark = cropWindowOnly(imgProfilesDark)
let winSettingsDark = cropWindowOnly(imgSettingsDark)
let winMainLight = cropWindowOnly(imgMainLight)

// MARK: - CoreGraphics Vector Helpers (Top-Left Origin Friendly)

func withCanvas(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    cg.setShouldSmoothFonts(true)
    draw(cg, CGSize(width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func savePNG(_ rep: NSBitmapImageRep, to url: URL) throws {
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    try data.write(to: url)
    print("Saved \(url.lastPathComponent) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

/// Draws text using AppKit's crisp SF Pro CoreText rendering in standard bottom-left CG coordinates.
func drawText(
    _ string: String,
    in rect: CGRect,
    font: NSFont,
    color: NSColor,
    alignment: NSTextAlignment = .left,
    kern: CGFloat = 0,
    lineSpacing: CGFloat = 0
) {
    let para = NSMutableParagraphStyle()
    para.alignment = alignment
    if lineSpacing > 0 { para.lineSpacing = lineSpacing }
    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    if kern != 0 { attrs[.kern] = kern }
    NSAttributedString(string: string, attributes: attrs).draw(in: rect)
}

func fillRoundedRect(_ cg: CGContext, rect: CGRect, radius: CGFloat, fill: NSColor, stroke: NSColor? = nil, lineWidth: CGFloat = 1.0) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.setFillColor(fill.cgColor)
    cg.fillPath()
    if let stroke {
        cg.addPath(path)
        cg.setStrokeColor(stroke.cgColor)
        cg.setLineWidth(lineWidth)
        cg.strokePath()
    }
    cg.restoreGState()
}

func drawClippedImage(_ cg: CGContext, image: CGImage, in rect: CGRect, radius: CGFloat, borderColor: NSColor? = nil, borderWidth: CGFloat = 1.5) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    cg.saveGState()
    cg.addPath(path)
    cg.clip()
    cg.interpolationQuality = .high
    cg.draw(image, in: rect)
    cg.restoreGState()

    if let borderColor {
        cg.saveGState()
        cg.addPath(path)
        cg.setStrokeColor(borderColor.cgColor)
        cg.setLineWidth(borderWidth)
        cg.strokePath()
        cg.restoreGState()
    }
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

func drawClaudeSyncIcon(_ cg: CGContext, rect: CGRect) {
    let radius = rect.width * 0.23
    let tileBg = NSColor(calibratedRed: 0.115, green: 0.125, blue: 0.15, alpha: 1.0)
    fillRoundedRect(cg, rect: rect, radius: radius, fill: tileBg, stroke: NSColor.white.withAlphaComponent(0.18), lineWidth: max(1.0, rect.width * 0.02))

    let starCenter = CGPoint(x: rect.minX + rect.width * 0.44, y: rect.minY + rect.height * 0.56)
    drawStarburst(cg, center: starCenter, outerRadius: rect.width * 0.34, color: Palette.terracotta.cgColor)

    let badgeR = rect.width * 0.19
    let badgeCenter = CGPoint(x: rect.maxX - badgeR - rect.width * 0.11, y: rect.minY + badgeR + rect.height * 0.11)
    let cutR = badgeR + rect.width * 0.036
    cg.setFillColor(tileBg.cgColor)
    cg.fillEllipse(in: CGRect(x: badgeCenter.x - cutR, y: badgeCenter.y - cutR, width: cutR * 2, height: cutR * 2))

    cg.setFillColor(NSColor.white.cgColor)
    cg.fillEllipse(in: CGRect(x: badgeCenter.x - badgeR, y: badgeCenter.y - badgeR, width: badgeR * 2, height: badgeR * 2))
    drawTransferArrows(cg, center: badgeCenter, radius: badgeR * 0.88, color: tileBg.cgColor, lineWidth: max(1.0, badgeR * 0.22))
}

func drawPill(_ cg: CGContext, text: String, centerX: CGFloat, y: CGFloat, height: CGFloat = 30, fill: NSColor = Palette.cardElevated, border: NSColor = Palette.hairlineDark, textColor: NSColor = Palette.textSecondary, fontSize: CGFloat = 12) {
    let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.9]
    let sz = (text as NSString).size(withAttributes: attrs)
    let w = sz.width + 28
    let rect = CGRect(x: centerX - w / 2, y: y, width: w, height: height)
    fillRoundedRect(cg, rect: rect, radius: height / 2, fill: fill, stroke: border, lineWidth: 1)
    drawText(
        text,
        in: CGRect(x: rect.minX, y: rect.minY + (height - sz.height) / 2 - 1, width: w, height: sz.height + 2),
        font: font,
        color: textColor,
        alignment: .center,
        kern: 0.9
    )
}

func drawSubtleDotGrid(_ cg: CGContext, size: CGSize, step: CGFloat = 36, alpha: CGFloat = 0.045) {
    cg.saveGState()
    cg.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
    var x: CGFloat = step / 2
    while x < size.width {
        var y: CGFloat = step / 2
        while y < size.height {
            cg.fillEllipse(in: CGRect(x: x - 0.8, y: y - 0.8, width: 1.6, height: 1.6))
            y += step
        }
        x += step
    }
    cg.restoreGState()
}

// MARK: - Visual 1: Hero Banner (1600×900 — Twitter Hero + GitHub Social Preview)

func generateHeroBanner() throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 34, alpha: 0.04)

        // Top symmetric brand row
        let iconSize: CGFloat = 34
        let brandW: CGFloat = 186
        let startX = (size.width - brandW) / 2
        let topY: CGFloat = 820
        drawClaudeSyncIcon(cg, rect: CGRect(x: startX, y: topY, width: iconSize, height: iconSize))
        drawText(
            "ClaudeSYNC",
            in: CGRect(x: startX + iconSize + 12, y: topY + 2, width: 150, height: 30),
            font: .systemFont(ofSize: 22, weight: .bold),
            color: Palette.textPrimary,
            kern: -0.4
        )

        // Editorial crisp 2-line headline (zero gradients, exact hierarchy)
        drawText(
            "Switch Claude accounts.",
            in: CGRect(x: 100, y: 736, width: 1400, height: 64),
            font: .systemFont(ofSize: 54, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.4
        )
        drawText(
            "Never lose your session.",
            in: CGRect(x: 100, y: 672, width: 1400, height: 64),
            font: .systemFont(ofSize: 54, weight: .bold),
            color: Palette.terracotta,
            alignment: .center,
            kern: -1.4
        )

        // Concise factual subcopy
        drawText(
            "Native macOS app to sync local Claude Code sessions, monitor 5h / 7d limits in the menu bar, and auto-failover without logging out.",
            in: CGRect(x: 180, y: 626, width: 1240, height: 32),
            font: .systemFont(ofSize: 18, weight: .regular),
            color: Palette.textSecondary,
            alignment: .center
        )

        // Symmetric pill strip
        drawPill(cg, text: "OPEN SOURCE · MIT", centerX: 590, y: 580, height: 28, fontSize: 11)
        drawPill(cg, text: "100% LOCAL · ZERO NETWORK", centerX: 800, y: 580, height: 28, fontSize: 11)
        drawPill(cg, text: "NATIVE SWIFTUI · 0% IDLE CPU", centerX: 1030, y: 580, height: 28, fontSize: 11)

        // Real Retina Desktop App rising cleanly from bottom edge
        let appW: CGFloat = 1040
        let appH: CGFloat = appW * (CGFloat(winMainDark.height) / CGFloat(winMainDark.width))
        let appRect = CGRect(x: (size.width - appW) / 2, y: 552 - appH, width: appW, height: appH)

        // Subtle crisp architectural shadow frame (flat offset, no neon bloom)
        fillRoundedRect(
            cg,
            rect: appRect.insetBy(dx: -1, dy: -1),
            radius: 19,
            fill: NSColor.black.withAlphaComponent(0.55)
        )
        drawClippedImage(cg, image: winMainDark, in: appRect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
    }

    try savePNG(rep, to: visualsOutURL.appendingPathComponent("01-hero-banner.png"))
    try savePNG(rep, to: assetsURL.appendingPathComponent("hero-banner.png"))
}

// MARK: - Visual 2: Symmetric 2×2 Feature Bento Grid (1600×1040)

func generateFeatureBento() throws {
    let rep = withCanvas(width: 1600, height: 1040) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 36, alpha: 0.035)

        // Top symmetric header
        drawClaudeSyncIcon(cg, rect: CGRect(x: 48, y: 954, width: 34, height: 34))
        drawText("ClaudeSYNC", in: CGRect(x: 94, y: 956, width: 220, height: 30), font: .systemFont(ofSize: 21, weight: .bold), color: Palette.textPrimary, kern: -0.4)
        drawText("Built for multi-account Claude Code workflows on macOS", in: CGRect(x: 340, y: 959, width: 1212, height: 26), font: .systemFont(ofSize: 16, weight: .medium), color: Palette.textSecondary, alignment: .right)

        let padX: CGFloat = 48
        let gutter: CGFloat = 22
        let cardW: CGFloat = (size.width - padX * 2 - gutter) / 2
        let cardH: CGFloat = 420
        let topRowY: CGFloat = 504
        let botRowY: CGFloat = 62

        let c1 = CGRect(x: padX, y: topRowY, width: cardW, height: cardH)
        let c2 = CGRect(x: padX + cardW + gutter, y: topRowY, width: cardW, height: cardH)
        let c3 = CGRect(x: padX, y: botRowY, width: cardW, height: cardH)
        let c4 = CGRect(x: padX + cardW + gutter, y: botRowY, width: cardW, height: cardH)

        func drawCardHeader(_ rect: CGRect, eyebrow: String, title: String, desc: String) {
            fillRoundedRect(cg, rect: rect, radius: 18, fill: Palette.cardBg, stroke: Palette.hairlineDark, lineWidth: 1.2)
            drawText(eyebrow, in: CGRect(x: rect.minX + 28, y: rect.maxY - 44, width: rect.width - 56, height: 18), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.terracotta, kern: 1.1)
            drawText(title, in: CGRect(x: rect.minX + 28, y: rect.maxY - 82, width: rect.width - 56, height: 34), font: .systemFont(ofSize: 25, weight: .bold), color: Palette.textPrimary, kern: -0.5)
            drawText(desc, in: CGRect(x: rect.minX + 28, y: rect.maxY - 114, width: rect.width - 56, height: 26), font: .systemFont(ofSize: 14, weight: .regular), color: Palette.textSecondary)
        }

        // Card 1: Menu Bar Limit Bars
        drawCardHeader(
            c1,
            eyebrow: "01 · MENU BAR TELEMETRY",
            title: "Retina limit bars in your top bar",
            desc: "Track both accounts (or 5h/7d windows) live — toggle icon ON/OFF anytime."
        )
        let mbPreviewRect = CGRect(x: c1.minX + 28, y: c1.minY + 24, width: c1.width - 56, height: 266)
        // Crop bottom 3 menu-bar strips from imgMenuBarBars cleanly
        let barsCrop = imgMenuBarBars.cropping(to: CGRect(x: 24, y: 218, width: imgMenuBarBars.width - 48, height: imgMenuBarBars.height - 244)) ?? imgMenuBarBars
        fillRoundedRect(cg, rect: mbPreviewRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let innerBars = mbPreviewRect.insetBy(dx: 14, dy: 14)
        let barsAspect = CGFloat(barsCrop.width) / CGFloat(barsCrop.height)
        var drawBarsRect = innerBars
        if innerBars.width / innerBars.height > barsAspect {
            let w = innerBars.height * barsAspect
            drawBarsRect = CGRect(x: innerBars.midX - w / 2, y: innerBars.minY, width: w, height: innerBars.height)
        } else {
            let h = innerBars.width / barsAspect
            drawBarsRect = CGRect(x: innerBars.minX, y: innerBars.midY - h / 2, width: innerBars.width, height: h)
        }
        drawClippedImage(cg, image: barsCrop, in: drawBarsRect, radius: 10)

        // Card 2: Zero-Logout Dual Profiles
        drawCardHeader(
            c2,
            eyebrow: "02 · ZERO-LOGOUT DUAL PROFILES",
            title: "Stay logged into both accounts",
            desc: "Launch isolated --user-data-dir profiles with local MCPs & history preserved."
        )
        let profSlice = winProfilesDark.cropping(to: CGRect(
            x: Int(Double(winProfilesDark.width) * 0.245),
            y: Int(Double(winProfilesDark.height) * 0.235),
            width: Int(Double(winProfilesDark.width) * 0.735),
            height: Int(Double(winProfilesDark.height) * 0.505)
        )) ?? winProfilesDark
        let profRect = CGRect(x: c2.minX + 28, y: c2.minY + 24, width: c2.width - 56, height: 266)
        fillRoundedRect(cg, rect: profRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let pInner = profRect.insetBy(dx: 12, dy: 12)
        let pAspect = CGFloat(profSlice.width) / CGFloat(profSlice.height)
        let pH = min(pInner.height, pInner.width / pAspect)
        let pW = pH * pAspect
        drawClippedImage(cg, image: profSlice, in: CGRect(x: pInner.midX - pW / 2, y: pInner.midY - pH / 2, width: pW, height: pH), radius: 10, borderColor: Palette.hairlineDark, borderWidth: 1)

        // Card 3: Live Limits & Auto-Failover
        drawCardHeader(
            c3,
            eyebrow: "03 · REAL-TIME LIMITS & AUTO FAILOVER",
            title: "Automatic switch on 429 or 95%",
            desc: "Reads local plan-usage-history & 429 resetsAt countdowns in real time."
        )
        let limSlice = winLimitsDark.cropping(to: CGRect(
            x: Int(Double(winLimitsDark.width) * 0.255),
            y: Int(Double(winLimitsDark.height) * 0.40),
            width: Int(Double(winLimitsDark.width) * 0.72),
            height: Int(Double(winLimitsDark.height) * 0.50)
        )) ?? winLimitsDark
        let limRect = CGRect(x: c3.minX + 28, y: c3.minY + 24, width: c3.width - 56, height: 266)
        fillRoundedRect(cg, rect: limRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let lInner = limRect.insetBy(dx: 12, dy: 12)
        let lAspect = CGFloat(limSlice.width) / CGFloat(limSlice.height)
        let lH = min(lInner.height, lInner.width / lAspect)
        let lW = lH * lAspect
        drawClippedImage(cg, image: limSlice, in: CGRect(x: lInner.midX - lW / 2, y: lInner.midY - lH / 2, width: lW, height: lH), radius: 10, borderColor: Palette.hairlineDark, borderWidth: 1)

        // Card 4: Auto Card Sync & Privacy Engineering
        drawCardHeader(
            c4,
            eyebrow: "04 · AUTO SHARED CARD SYNC & SAFETY",
            title: "Work in Account B. Stay synced in A.",
            desc: "Shared session cards mirror silently in the background — zero cloud calls."
        )
        let diagRect = CGRect(x: c4.minX + 28, y: c4.minY + 24, width: c4.width - 56, height: 266)
        fillRoundedRect(cg, rect: diagRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)

        // Clean 3-box horizontal architecture schematic inside Card 4
        let boxW: CGFloat = 178
        let boxH: CGFloat = 94
        let midY = diagRect.minY + 132
        let b1 = CGRect(x: diagRect.minX + 24, y: midY, width: boxW, height: boxH)
        let b2 = CGRect(x: diagRect.midX - boxW / 2, y: midY, width: boxW, height: boxH)
        let b3 = CGRect(x: diagRect.maxX - 24 - boxW, y: midY, width: boxW, height: boxH)

        fillRoundedRect(cg, rect: b1, radius: 12, fill: Palette.cardBg, stroke: Palette.appleGreen.withAlphaComponent(0.45), lineWidth: 1.2)
        drawText("Account 1", in: CGRect(x: b1.minX + 12, y: b1.maxY - 34, width: b1.width - 24, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText("local_X.json\n142 turns", in: CGRect(x: b1.minX + 10, y: b1.minY + 14, width: b1.width - 20, height: 38), font: .monospacedSystemFont(ofSize: 11.5, weight: .medium), color: Palette.textSecondary, alignment: .center)

        fillRoundedRect(cg, rect: b2, radius: 12, fill: Palette.cardElevated, stroke: Palette.terracotta.withAlphaComponent(0.60), lineWidth: 1.4)
        drawText("Shared Transcript", in: CGRect(x: b2.minX + 8, y: b2.maxY - 34, width: b2.width - 16, height: 22), font: .systemFont(ofSize: 14, weight: .bold), color: Palette.terracotta, alignment: .center)
        drawText("~/.claude/projects/\n<cliId>.jsonl", in: CGRect(x: b2.minX + 8, y: b2.minY + 14, width: b2.width - 16, height: 38), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: Palette.textPrimary, alignment: .center)

        fillRoundedRect(cg, rect: b3, radius: 12, fill: Palette.cardBg, stroke: Palette.appleBlue.withAlphaComponent(0.45), lineWidth: 1.2)
        drawText("Account 2", in: CGRect(x: b3.minX + 12, y: b3.maxY - 34, width: b3.width - 24, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText("local_X.json\nAuto-Synced ✓", in: CGRect(x: b3.minX + 10, y: b3.minY + 14, width: b3.width - 20, height: 38), font: .monospacedSystemFont(ofSize: 11.5, weight: .medium), color: Palette.appleGreen, alignment: .center)

        // Connectors
        cg.saveGState()
        cg.setStrokeColor(Palette.hairlineStrong.cgColor)
        cg.setLineWidth(1.8)
        cg.move(to: CGPoint(x: b1.maxX + 6, y: b1.midY))
        cg.addLine(to: CGPoint(x: b2.minX - 6, y: b2.midY))
        cg.move(to: CGPoint(x: b2.maxX + 6, y: b2.midY))
        cg.addLine(to: CGPoint(x: b3.minX - 6, y: b3.midY))
        cg.strokePath()
        cg.restoreGState()

        // Bottom 3 safety specs cleanly symmetric
        let specY = diagRect.minY + 26
        let specW = (diagRect.width - 48 - 20) / 3
        let specs: [(String, String)] = [
            ("Zero Credentials", "Never reads Cookies or Keychain"),
            ("Auto Backups", "Timestamped restore before write"),
            ("Atomic 0600", "Strips cloud bridgeSessionIds")
        ]
        for (i, spec) in specs.enumerated() {
            let sx = diagRect.minX + 24 + CGFloat(i) * (specW + 10)
            let sRect = CGRect(x: sx, y: specY, width: specW, height: 74)
            fillRoundedRect(cg, rect: sRect, radius: 10, fill: Palette.cardBg, stroke: Palette.hairlineDark, lineWidth: 1)
            drawText(spec.0, in: CGRect(x: sRect.minX + 10, y: sRect.maxY - 30, width: sRect.width - 20, height: 20), font: .systemFont(ofSize: 12.5, weight: .semibold), color: Palette.textPrimary, alignment: .center)
            drawText(spec.1, in: CGRect(x: sRect.minX + 10, y: sRect.minY + 12, width: sRect.width - 20, height: 30), font: .systemFont(ofSize: 10.5, weight: .regular), color: Palette.textSecondary, alignment: .center)
        }
    }

    try savePNG(rep, to: visualsOutURL.appendingPathComponent("02-bento-features.png"))
}

// MARK: - Visual 3: Architecture Diagram (1600×900 — Why & How It Works)

func generateArchitectureVisual() throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 36, alpha: 0.04)

        // Header
        drawPill(cg, text: "HOW CLAUDESYNC WORKS UNDER THE HOOD", centerX: size.width / 2, y: 822, height: 28, textColor: Palette.terracotta, fontSize: 11)
        drawText(
            "Local-first architecture. Zero credential hacks.",
            in: CGRect(x: 100, y: 748, width: 1400, height: 56),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )
        drawText(
            "Claude Desktop already shares conversation transcripts on disk. ClaudeSYNC safely bridges the per-account index cards.",
            in: CGRect(x: 200, y: 706, width: 1200, height: 30),
            font: .systemFont(ofSize: 17, weight: .regular),
            color: Palette.textSecondary,
            alignment: .center
        )

        // Three Symmetric Columns: Profile 1 | ClaudeSYNC Engine | Profile 2
        let colW: CGFloat = 440
        let colH: CGFloat = 460
        let colY: CGFloat = 176
        let gap: CGFloat = 60
        let startX = (size.width - (colW * 3 + gap * 2)) / 2

        let leftCol = CGRect(x: startX, y: colY, width: colW, height: colH)
        let midCol = CGRect(x: startX + colW + gap, y: colY, width: colW, height: colH)
        let rightCol = CGRect(x: startX + (colW + gap) * 2, y: colY, width: colW, height: colH)

        // Left: Account 1
        fillRoundedRect(cg, rect: leftCol, radius: 18, fill: Palette.cardBg, stroke: Palette.appleGreen.withAlphaComponent(0.35), lineWidth: 1.2)
        drawText("PROFILE 1 · ACCOUNT A", in: CGRect(x: leftCol.minX + 26, y: leftCol.maxY - 42, width: colW - 52, height: 18), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.appleGreen, kern: 1.0)
        drawText("Claude Desktop (Primary)", in: CGRect(x: leftCol.minX + 26, y: leftCol.maxY - 76, width: colW - 52, height: 28), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.textPrimary)

        let leftBoxes: [(String, String, String)] = [
            ("Session Index Cards", "~/Library/Application Support/Claude/\nclaude-code-sessions/<acc1>/<org1>/", "local_*.json"),
            ("Usage Telemetry", "plan-usage-history.json", "5h / 7d / xu"),
            ("Live Process State", "claude --resume=<cliSessionId>", "Active PID")
        ]
        for (i, item) in leftBoxes.enumerated() {
            let r = CGRect(x: leftCol.minX + 24, y: leftCol.maxY - 188 - CGFloat(i) * 108, width: colW - 48, height: 92)
            fillRoundedRect(cg, rect: r, radius: 12, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
            drawText(item.0, in: CGRect(x: r.minX + 16, y: r.maxY - 32, width: r.width - 110, height: 20), font: .systemFont(ofSize: 14, weight: .semibold), color: Palette.textPrimary)
            drawText(item.2, in: CGRect(x: r.maxX - 110, y: r.maxY - 31, width: 96, height: 18), font: .monospacedSystemFont(ofSize: 10.5, weight: .semibold), color: Palette.appleGreen, alignment: .right)
            drawText(item.1, in: CGRect(x: r.minX + 16, y: r.minY + 12, width: r.width - 32, height: 40), font: .monospacedSystemFont(ofSize: 11.5, weight: .regular), color: Palette.textSecondary)
        }

        // Center: ClaudeSYNC Engine
        fillRoundedRect(cg, rect: midCol, radius: 18, fill: Palette.cardElevated, stroke: Palette.terracotta.withAlphaComponent(0.55), lineWidth: 1.5)
        drawClaudeSyncIcon(cg, rect: CGRect(x: midCol.midX - 24, y: midCol.maxY - 72, width: 48, height: 48))
        drawText("ClaudeSYNC Engine", in: CGRect(x: midCol.minX + 20, y: midCol.maxY - 114, width: colW - 40, height: 30), font: .systemFont(ofSize: 23, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText("Pure Swift · Local Filesystem Only", in: CGRect(x: midCol.minX + 20, y: midCol.maxY - 138, width: colW - 40, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: Palette.terracotta, alignment: .center)

        let steps: [(String, String)] = [
            ("1. Shared Transcript Verification", "Confirms ~/.claude/projects/<cliId>.jsonl on disk"),
            ("2. Cross-Account Hygiene", "Strips bridgeSessionIds & remoteMcpServersConfig"),
            ("3. Atomic Backup & Write", "Timestamped backup + atomic 0600 JSON write"),
            ("4. Auto Card Mirror & Failover", "Keeps shared cards equal + switches on 429")
        ]
        for (i, step) in steps.enumerated() {
            let r = CGRect(x: midCol.minX + 24, y: midCol.maxY - 224 - CGFloat(i) * 74, width: colW - 48, height: 62)
            fillRoundedRect(cg, rect: r, radius: 10, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
            drawText(step.0, in: CGRect(x: r.minX + 14, y: r.maxY - 27, width: r.width - 28, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: Palette.textPrimary)
            drawText(step.1, in: CGRect(x: r.minX + 14, y: r.minY + 10, width: r.width - 28, height: 18), font: .systemFont(ofSize: 11.5, weight: .regular), color: Palette.textSecondary)
        }

        // Right: Account 2
        fillRoundedRect(cg, rect: rightCol, radius: 18, fill: Palette.cardBg, stroke: Palette.appleBlue.withAlphaComponent(0.35), lineWidth: 1.2)
        drawText("PROFILE 2 · ACCOUNT B", in: CGRect(x: rightCol.minX + 26, y: rightCol.maxY - 42, width: colW - 52, height: 18), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.appleBlue, kern: 1.0)
        drawText("Claude Desktop (Isolated)", in: CGRect(x: rightCol.minX + 26, y: rightCol.maxY - 76, width: colW - 52, height: 28), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.textPrimary)

        let rightBoxes: [(String, String, String)] = [
            ("Isolated --user-data-dir", "~/Library/Application Support/\nClaude-Account2/", "Zero Logout"),
            ("Synced Sidebar Cards", "Instant top-of-sidebar continuity\nwith full conversation context", "Auto Mirror"),
            ("Shared Transcript Layer", "~/.claude/projects/*/*.jsonl\nZero duplication, single source of truth", "Shared Disk")
        ]
        for (i, item) in rightBoxes.enumerated() {
            let r = CGRect(x: rightCol.minX + 24, y: rightCol.maxY - 188 - CGFloat(i) * 108, width: colW - 48, height: 92)
            fillRoundedRect(cg, rect: r, radius: 12, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
            drawText(item.0, in: CGRect(x: r.minX + 16, y: r.maxY - 32, width: r.width - 110, height: 20), font: .systemFont(ofSize: 14, weight: .semibold), color: Palette.textPrimary)
            drawText(item.2, in: CGRect(x: r.maxX - 110, y: r.maxY - 31, width: 96, height: 18), font: .monospacedSystemFont(ofSize: 10.5, weight: .semibold), color: Palette.appleBlue, alignment: .right)
            drawText(item.1, in: CGRect(x: r.minX + 16, y: r.minY + 12, width: r.width - 32, height: 40), font: .monospacedSystemFont(ofSize: 11.5, weight: .regular), color: Palette.textSecondary)
        }

        // Crisp horizontal double-headed arrows linking the 3 columns
        cg.saveGState()
        cg.setStrokeColor(Palette.terracotta.cgColor)
        cg.setLineWidth(2.2)
        cg.setLineCap(.round)
        let arrowY = colY + colH / 2
        for (x1, x2) in [(leftCol.maxX + 8, midCol.minX - 8), (midCol.maxX + 8, rightCol.minX - 8)] {
            cg.move(to: CGPoint(x: x1, y: arrowY))
            cg.addLine(to: CGPoint(x: x2, y: arrowY))
            cg.move(to: CGPoint(x: x2 - 8, y: arrowY + 7))
            cg.addLine(to: CGPoint(x: x2, y: arrowY))
            cg.addLine(to: CGPoint(x: x2 - 8, y: arrowY - 7))
            cg.move(to: CGPoint(x: x1 + 8, y: arrowY + 7))
            cg.addLine(to: CGPoint(x: x1, y: arrowY))
            cg.addLine(to: CGPoint(x: x1 + 8, y: arrowY - 7))
        }
        cg.strokePath()
        cg.restoreGState()

        // Bottom clean engineering spec footer
        let footerRect = CGRect(x: startX, y: 66, width: size.width - startX * 2, height: 68)
        fillRoundedRect(cg, rect: footerRect, radius: 14, fill: Palette.cardBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let footerItems = [
            "Native SwiftUI + AppKit",
            "Zero Electron Bloat (1.3 MB DMG)",
            "Zero Network / Zero Telemetry",
            "github.com/berkayildize/ClaudeSYNC"
        ]
        let fStep = footerRect.width / CGFloat(footerItems.count)
        for (i, label) in footerItems.enumerated() {
            let fx = footerRect.minX + CGFloat(i) * fStep
            drawText(
                label,
                in: CGRect(x: fx + 8, y: footerRect.midY - 10, width: fStep - 16, height: 22),
                font: i == 3 ? .monospacedSystemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13.5, weight: .semibold),
                color: i == 3 ? Palette.terracotta : Palette.textPrimary,
                alignment: .center
            )
            if i < footerItems.count - 1 {
                cg.setFillColor(Palette.hairlineDark.cgColor)
                cg.fill(CGRect(x: fx + fStep, y: footerRect.minY + 18, width: 1, height: footerRect.height - 36))
            }
        }
    }

    try savePNG(rep, to: visualsOutURL.appendingPathComponent("03-architecture.png"))
}

// MARK: - Visual 4: Dark & Light Native macOS Split Showcase (1600×900)

func generateDarkLightShowcase() throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        // Exact 50/50 split background: Obsidian Left | Alabaster Right
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        cg.setFillColor(Palette.lightBg.cgColor)
        cg.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))

        // Crisp center hairline seam
        cg.setFillColor(NSColor.gray.withAlphaComponent(0.25).cgColor)
        cg.fill(CGRect(x: size.width / 2 - 0.5, y: 0, width: 1, height: size.height))

        // Left & Right aligned captions
        drawText("DARK MODE", in: CGRect(x: 56, y: 824, width: 320, height: 22), font: .systemFont(ofSize: 12, weight: .bold), color: Palette.terracotta, kern: 1.4)
        drawText("Native macOS Glass.", in: CGRect(x: 56, y: 774, width: 680, height: 46), font: .systemFont(ofSize: 38, weight: .bold), color: Palette.textPrimary, kern: -0.9)

        drawText("LIGHT MODE", in: CGRect(x: size.width / 2 + 56, y: 824, width: 320, height: 22), font: .systemFont(ofSize: 12, weight: .bold), color: Palette.terracotta, kern: 1.4)
        drawText("120Hz ProMotion. Zero Gradients.", in: CGRect(x: size.width / 2 + 56, y: 774, width: 700, height: 46), font: .systemFont(ofSize: 38, weight: .bold), color: NSColor(calibratedWhite: 0.11, alpha: 1.0), kern: -0.9)

        let cardW: CGFloat = 716
        let cardH: CGFloat = cardW * (CGFloat(winMainDark.height) / CGFloat(winMainDark.width))
        let yPos: CGFloat = (736 - cardH) / 2 + 12

        let leftRect = CGRect(x: (size.width / 2 - cardW) / 2, y: yPos, width: cardW, height: cardH)
        let rightRect = CGRect(x: size.width / 2 + (size.width / 2 - cardW) / 2, y: yPos, width: cardW, height: cardH)

        drawClippedImage(cg, image: winMainDark, in: leftRect, radius: 15, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        drawClippedImage(cg, image: winMainLight, in: rightRect, radius: 15, borderColor: NSColor.black.withAlphaComponent(0.14), borderWidth: 1.5)

        // Centered floating brand pill across the seam at bottom
        drawPill(
            cg,
            text: "ClaudeSYNC · github.com/berkayildize/ClaudeSYNC",
            centerX: size.width / 2,
            y: 36,
            height: 36,
            fill: Palette.cardBg,
            border: Palette.hairlineStrong,
            textColor: Palette.textPrimary,
            fontSize: 13
        )
    }

    try savePNG(rep, to: visualsOutURL.appendingPathComponent("04-dark-light-split.png"))
}

// MARK: - 1080p60 Launch Promo Video (AVAssetWriter Hardware H.264 — 22s, 1320 Frames)

func easeOutCubic(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return 1.0 - pow(1.0 - x, 3.0)
}

func easeInOutCubic(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

func drawVideoFrame(cg: CGContext, time: Double) {
    let w: CGFloat = 1920
    let h: CGFloat = 1080
    let size = CGSize(width: w, height: h)

    // Matte obsidian studio backdrop
    cg.setFillColor(Palette.canvasBg.cgColor)
    cg.fill(CGRect(origin: .zero, size: size))
    drawSubtleDotGrid(cg, size: size, step: 40, alpha: 0.036)

    // Subtle thin progress rail along the very bottom (Apple Keynote style)
    let progress = CGFloat(clamp01(time / 22.0))
    cg.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: w, height: 3))
    cg.setFillColor(Palette.terracotta.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: w * progress, height: 3))

    // Helper for smooth scene alpha envelopes
    func sceneAlpha(start: Double, end: Double, fadeIn: Double = 0.45, fadeOut: Double = 0.40) -> Double {
        let aIn = easeOutCubic((time - start) / fadeIn)
        let aOut = 1.0 - easeInOutCubic((time - (end - fadeOut)) / fadeOut)
        return clamp01(min(aIn, aOut))
    }

    // ------------------------------------------------------------------
    // SCENE 1 (0.0s – 3.8s): Hook — Problem & Brand Reveal
    // ------------------------------------------------------------------
    if time < 4.0 {
        let a = sceneAlpha(start: 0.0, end: 3.8, fadeIn: 0.5, fadeOut: 0.45)
        let pIcon = easeOutCubic(time / 0.75)
        let pLine1 = easeOutCubic((time - 0.35) / 0.65)
        let pLine2 = easeOutCubic((time - 0.75) / 0.65)
        let pSub = easeOutCubic((time - 1.15) / 0.65)

        cg.saveGState()
        cg.setAlpha(a)

        // Centered ClaudeSYNC Icon
        let iconSz: CGFloat = 88 * (0.86 + 0.14 * CGFloat(pIcon))
        drawClaudeSyncIcon(cg, rect: CGRect(x: (w - iconSz) / 2, y: 690 - (1 - CGFloat(pIcon)) * 18, width: iconSz, height: iconSz))

        // Headline
        cg.saveGState()
        cg.setAlpha(a * pLine1)
        drawText(
            "Hit a Claude rate limit?",
            in: CGRect(x: 160, y: 560 - (1 - CGFloat(pLine1)) * 22, width: w - 320, height: 84),
            font: .systemFont(ofSize: 72, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.8
        )
        cg.restoreGState()

        cg.saveGState()
        cg.setAlpha(a * pLine2)
        drawText(
            "Keep your exact session.",
            in: CGRect(x: 160, y: 472 - (1 - CGFloat(pLine2)) * 22, width: w - 320, height: 84),
            font: .systemFont(ofSize: 72, weight: .bold),
            color: Palette.terracotta,
            alignment: .center,
            kern: -1.8
        )
        cg.restoreGState()

        cg.saveGState()
        cg.setAlpha(a * pSub)
        drawPill(cg, text: "INTRODUCING CLAUDESYNC FOR MACOS · OPEN SOURCE", centerX: w / 2, y: 382 - (1 - CGFloat(pSub)) * 12, height: 38, fontSize: 13)
        cg.restoreGState()

        cg.restoreGState()
    }

    // ------------------------------------------------------------------
    // SCENE 2 (3.5s – 8.2s): Full Desktop App Reveal (Sessions)
    // ------------------------------------------------------------------
    if time >= 3.4 && time < 8.4 {
        let local = time - 3.5
        let a = sceneAlpha(start: 3.5, end: 8.2, fadeIn: 0.55, fadeOut: 0.45)
        let enter = easeOutCubic(local / 0.85)
        let slowScale = 0.96 + 0.04 * CGFloat(enter) + 0.012 * CGFloat(clamp01(local / 4.7))

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: "01 · NATIVE MACOS DESKTOP APP", centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            "Every session, synced across both accounts.",
            in: CGRect(x: 160, y: 908, width: w - 320, height: 60),
            font: .systemFont(ofSize: 46, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.2
        )

        let baseW: CGFloat = 1120 * slowScale
        let baseH: CGFloat = baseW * (CGFloat(winMainDark.height) / CGFloat(winMainDark.width))
        let yOffset = (1 - CGFloat(enter)) * 50
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - yOffset, width: baseW, height: baseH)
        drawClippedImage(cg, image: winMainDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // ------------------------------------------------------------------
    // SCENE 3 (7.9s – 12.2s): Live Limits & Auto-Failover
    // ------------------------------------------------------------------
    if time >= 7.8 && time < 12.4 {
        let local = time - 7.9
        let a = sceneAlpha(start: 7.9, end: 12.2, fadeIn: 0.5, fadeOut: 0.45)
        let enter = easeOutCubic(local / 0.8)
        let drift = CGFloat(clamp01(local / 4.3))

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: "02 · REAL-TIME LIMITS & AUTO FAILOVER", centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            "Live 5h / 7d gauges, reset countdowns, automatic switch on 429.",
            in: CGRect(x: 120, y: 908, width: w - 240, height: 60),
            font: .systemFont(ofSize: 42, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.0
        )

        let baseW: CGFloat = 1120 * (0.97 + 0.03 * CGFloat(enter) + 0.015 * drift)
        let baseH: CGFloat = baseW * (CGFloat(winLimitsDark.height) / CGFloat(winLimitsDark.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 36, width: baseW, height: baseH)
        drawClippedImage(cg, image: winLimitsDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // ------------------------------------------------------------------
    // SCENE 4 (11.9s – 15.6s): Zero-Logout Dual Profiles
    // ------------------------------------------------------------------
    if time >= 11.8 && time < 15.8 {
        let local = time - 11.9
        let a = sceneAlpha(start: 11.9, end: 15.6, fadeIn: 0.5, fadeOut: 0.45)
        let enter = easeOutCubic(local / 0.75)

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: "03 · ZERO-LOGOUT DUAL PROFILES (--user-data-dir)", centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            "Stay signed into both Ultra accounts. Switch in one click.",
            in: CGRect(x: 140, y: 908, width: w - 280, height: 60),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )

        let baseW: CGFloat = 1120 * (0.97 + 0.03 * CGFloat(enter))
        let baseH: CGFloat = baseW * (CGFloat(winProfilesDark.height) / CGFloat(winProfilesDark.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 36, width: baseW, height: baseH)
        drawClippedImage(cg, image: winProfilesDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // ------------------------------------------------------------------
    // SCENE 5 (15.3s – 18.9s): Retina Menu Bar Bars + Light Mode Split
    // ------------------------------------------------------------------
    if time >= 15.2 && time < 19.1 {
        let local = time - 15.3
        let a = sceneAlpha(start: 15.3, end: 18.9, fadeIn: 0.5, fadeOut: 0.45)
        let enter = easeOutCubic(local / 0.75)

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: "04 · RETINA MENU BAR BARS & LIGHT MODE", centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            "Glanceable top-bar limits. Toggle menu bar ON or OFF anytime.",
            in: CGRect(x: 140, y: 908, width: w - 280, height: 60),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )

        // Symmetric 2-card composition: Left Menu Bar Bars Showcase | Right Light Mode App
        let yBase: CGFloat = 148 - (1 - CGFloat(enter)) * 30
        let leftCard = CGRect(x: 110, y: yBase, width: 740, height: 700)
        let rightCard = CGRect(x: 890, y: yBase, width: 920, height: 700)

        fillRoundedRect(cg, rect: leftCard, radius: 18, fill: Palette.cardBg, stroke: Palette.hairlineStrong, lineWidth: 1.2)
        let mbAspect = CGFloat(imgMenuBarBars.width) / CGFloat(imgMenuBarBars.height)
        let mbW = leftCard.width - 56
        let mbH = mbW / mbAspect
        drawClippedImage(cg, image: imgMenuBarBars, in: CGRect(x: leftCard.midX - mbW / 2, y: leftCard.midY - mbH / 2, width: mbW, height: mbH), radius: 14)

        let lAspect = CGFloat(winMainLight.width) / CGFloat(winMainLight.height)
        let lW = rightCard.width
        let lH = lW / lAspect
        drawClippedImage(cg, image: winMainLight, in: CGRect(x: rightCard.minX, y: rightCard.midY - lH / 2, width: lW, height: lH), radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // ------------------------------------------------------------------
    // SCENE 6 (18.6s – 22.0s): Open-Source Outro CTA
    // ------------------------------------------------------------------
    if time >= 18.5 {
        let local = time - 18.6
        let a = easeOutCubic(local / 0.55)
        let rise = (1 - CGFloat(a)) * 24

        cg.saveGState()
        cg.setAlpha(a)

        let iconSz: CGFloat = 112
        drawClaudeSyncIcon(cg, rect: CGRect(x: (w - iconSz) / 2, y: 656 - rise, width: iconSz, height: iconSz))

        drawText(
            "ClaudeSYNC",
            in: CGRect(x: 200, y: 546 - rise, width: w - 400, height: 92),
            font: .systemFont(ofSize: 76, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -2.0
        )

        drawText(
            "100% Local · Zero Telemetry · MIT Open Source",
            in: CGRect(x: 200, y: 484 - rise, width: w - 400, height: 38),
            font: .systemFont(ofSize: 24, weight: .medium),
            color: Palette.textSecondary,
            alignment: .center
        )

        drawPill(
            cg,
            text: "github.com/berkayildize/ClaudeSYNC",
            centerX: w / 2,
            y: 382 - rise,
            height: 52,
            fill: Palette.cardElevated,
            border: Palette.terracotta.withAlphaComponent(0.75),
            textColor: Palette.textPrimary,
            fontSize: 20
        )

        drawText(
            "macOS 14+ · Native SwiftUI & AppKit · 1.3 MB DMG",
            in: CGRect(x: 200, y: 316 - rise, width: w - 400, height: 28),
            font: .monospacedSystemFont(ofSize: 15, weight: .medium),
            color: Palette.textTertiary,
            alignment: .center
        )

        cg.restoreGState()
    }
}

func generateLaunchVideo() throws {
    let mp4URL = videoOutURL.appendingPathComponent("ClaudeSYNC-Launch-1080p60.mp4")
    try? FileManager.default.removeItem(at: mp4URL)

    let width = 1920
    let height = 1080
    let fps: Int32 = 60
    let durationSec = 22.0
    let totalFrames = Int(durationSec * Double(fps))

    let writer = try AVAssetWriter(outputURL: mp4URL, fileType: .mp4)
    let videoSettings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: 14_000_000,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalKey: 60
        ]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    input.expectsMediaDataInRealTime = false

    let adaptor = AVAssetWriterInputPixelBufferAdaptor(
        assetWriterInput: input,
        sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
    )

    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)

    let keyframeTimes: [Int: String] = [
        Int(1.9 * 60): "kf-01-hook.png",
        Int(5.5 * 60): "kf-02-app.png",
        Int(9.8 * 60): "kf-03-limits.png",
        Int(13.6 * 60): "kf-04-profiles.png",
        Int(17.1 * 60): "kf-05-menubar-light.png",
        Int(20.6 * 60): "kf-06-outro.png"
    ]

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    for frameIdx in 0..<totalFrames {
        while !input.isReadyForMoreMediaData {
            Thread.sleep(forTimeInterval: 0.002)
        }

        autoreleasepool {
            guard let pool = adaptor.pixelBufferPool else { return }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBuffer)
            guard let pb = pixelBuffer else { return }

            CVPixelBufferLockBaseAddress(pb, [])
            defer { CVPixelBufferUnlockBaseAddress(pb, []) }

            guard let cg = CGContext(
                data: CVPixelBufferGetBaseAddress(pb),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else { return }

            let nsCtx = NSGraphicsContext(cgContext: cg, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = nsCtx
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)

            let t = Double(frameIdx) / Double(fps)
            drawVideoFrame(cg: cg, time: t)

            NSGraphicsContext.restoreGraphicsState()

            if let kfName = keyframeTimes[frameIdx], let cgSnap = cg.makeImage() {
                let rep = NSBitmapImageRep(cgImage: cgSnap)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: keyframesOutURL.appendingPathComponent(kfName))
                }
            }

            let pts = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
            adaptor.append(pb, withPresentationTime: pts)
        }
    }

    input.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting {
        sem.signal()
    }
    sem.wait()

    if writer.status != .completed {
        fatalError("AVAssetWriter failed: \(String(describing: writer.error))")
    }
    print("Saved \(mp4URL.lastPathComponent) (1920x1080 @ 60fps, \(totalFrames) frames)")
}

// MARK: - Run All Generators

print("==> Generating ClaudeSYNC Launch Visuals...")
try generateHeroBanner()
try generateFeatureBento()
try generateArchitectureVisual()
try generateDarkLightShowcase()

if !CommandLine.arguments.contains("--visuals-only") {
    print("==> Rendering 1080p60 Launch Promo Video (AVAssetWriter H.264)...")
    try generateLaunchVideo()
}
print("==> Launch Kit complete!")
