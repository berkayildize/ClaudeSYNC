#!/usr/bin/env swift
import AppKit
import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation

// MARK: - Language Spec

enum KitLang: String, CaseIterable {
    case en
    case tr

    var isTurkish: Bool { self == .tr }
    var suffix: String { rawValue }
    var upper: String { rawValue.uppercased() }
}

struct KitCopy {
    let lang: KitLang
    func t(_ tr: String, _ en: String) -> String { lang.isTurkish ? tr : en }
}

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
}

// MARK: - Loaded Per-Language Retina Assets

struct LangAssets {
    let winMainDark: CGImage
    let winLimitsDark: CGImage
    let winProfilesDark: CGImage
    let winSettingsDark: CGImage
    let winMainLight: CGImage
    let winOnboardingWelcome: CGImage
    let winOnboardingPerms: CGImage
    let imgMenuBarBars: CGImage

    static func load(from dir: URL) -> LangAssets {
        func loadCG(_ name: String) -> CGImage {
            let url = dir.appendingPathComponent(name)
            guard let img = NSImage(contentsOf: url),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                fatalError("Missing asset: \(url.path)")
            }
            return cg
        }
        func cropWindow(_ img: CGImage, padPx: Int = 56) -> CGImage {
            let rect = CGRect(
                x: padPx,
                y: padPx,
                width: max(1, img.width - padPx * 2),
                height: max(1, img.height - padPx * 2)
            )
            return img.cropping(to: rect) ?? img
        }
        return LangAssets(
            winMainDark: cropWindow(loadCG("app-main-dark.png")),
            winLimitsDark: cropWindow(loadCG("app-limits-dark.png")),
            winProfilesDark: cropWindow(loadCG("app-profiles-dark.png")),
            winSettingsDark: cropWindow(loadCG("app-settings-dark.png")),
            winMainLight: cropWindow(loadCG("app-main-light.png")),
            winOnboardingWelcome: cropWindow(loadCG("app-onboarding-welcome-dark.png")),
            winOnboardingPerms: cropWindow(loadCG("app-onboarding-permissions-dark.png")),
            imgMenuBarBars: loadCG("menubar-bars.png")
        )
    }
}

// MARK: - CoreGraphics Vector Helpers

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
    print("Saved \(url.path) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
}

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
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .kern: 0.85]
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
        kern: 0.85
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

// MARK: - Visual 1: Hero Banner (1600×900)

func generateHeroBanner(copy: KitCopy, assets: LangAssets, outURL: URL, docsCopyURL: URL?) throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 34, alpha: 0.04)

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

        drawText(
            copy.t("Claude hesapları arasında geç.", "Switch Claude accounts."),
            in: CGRect(x: 100, y: 736, width: 1400, height: 64),
            font: .systemFont(ofSize: 54, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.4
        )
        drawText(
            copy.t("Oturumunu asla kaybetme.", "Never lose your session."),
            in: CGRect(x: 100, y: 672, width: 1400, height: 64),
            font: .systemFont(ofSize: 54, weight: .bold),
            color: Palette.terracotta,
            alignment: .center,
            kern: -1.4
        )

        drawText(
            copy.t(
                "Yerel Claude Code oturumlarını eşitleyen, 5s / 7g limitlerini üst barda gösteren ve çıkışsız otomatik geçiş yapan native macOS uygulaması.",
                "Native macOS app to sync local Claude Code sessions, monitor 5h / 7d limits in the menu bar, and auto-failover without logging out."
            ),
            in: CGRect(x: 140, y: 626, width: 1320, height: 32),
            font: .systemFont(ofSize: 17.5, weight: .regular),
            color: Palette.textSecondary,
            alignment: .center
        )

        drawPill(cg, text: copy.t("AÇIK KAYNAK · MIT", "OPEN SOURCE · MIT"), centerX: 560, y: 580, height: 28, fontSize: 11)
        drawPill(cg, text: copy.t("%100 YEREL · SIFIR AĞ", "100% LOCAL · ZERO NETWORK"), centerX: 790, y: 580, height: 28, fontSize: 11)
        drawPill(cg, text: copy.t("NATIVE SWIFTUI · TR & EN", "NATIVE SWIFTUI · EN & TR"), centerX: 1030, y: 580, height: 28, fontSize: 11)

        let appW: CGFloat = 1040
        let appH: CGFloat = appW * (CGFloat(assets.winMainDark.height) / CGFloat(assets.winMainDark.width))
        let appRect = CGRect(x: (size.width - appW) / 2, y: 552 - appH, width: appW, height: appH)

        fillRoundedRect(cg, rect: appRect.insetBy(dx: -1, dy: -1), radius: 19, fill: NSColor.black.withAlphaComponent(0.55))
        drawClippedImage(cg, image: assets.winMainDark, in: appRect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
    }

    try savePNG(rep, to: outURL)
    if let docsCopyURL { try savePNG(rep, to: docsCopyURL) }
}

// MARK: - Visual 2: Symmetric 2×2 Feature Bento Grid (1600×1040)

func generateFeatureBento(copy: KitCopy, assets: LangAssets, outURL: URL, docsCopyURL: URL?) throws {
    let rep = withCanvas(width: 1600, height: 1040) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 36, alpha: 0.035)

        drawClaudeSyncIcon(cg, rect: CGRect(x: 48, y: 954, width: 34, height: 34))
        drawText("ClaudeSYNC", in: CGRect(x: 94, y: 956, width: 220, height: 30), font: .systemFont(ofSize: 21, weight: .bold), color: Palette.textPrimary, kern: -0.4)
        drawText(
            copy.t("macOS'ta çoklu Claude Code hesabı kullanan geliştiriciler için", "Built for multi-account Claude Code workflows on macOS"),
            in: CGRect(x: 340, y: 959, width: 1212, height: 26),
            font: .systemFont(ofSize: 16, weight: .medium),
            color: Palette.textSecondary,
            alignment: .right
        )

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
            eyebrow: copy.t("01 · ÜST BAR TELEMETRİSİ", "01 · MENU BAR TELEMETRY"),
            title: copy.t("Üst barda Retina limit barları", "Retina limit bars in your top bar"),
            desc: copy.t("İki hesabı (veya 5s/7g) canlı izleyin — simgeyi istediğiniz an kapatın.", "Track both accounts (or 5h/7d windows) live — toggle icon ON/OFF anytime.")
        )
        let mbPreviewRect = CGRect(x: c1.minX + 28, y: c1.minY + 24, width: c1.width - 56, height: 266)
        let barsCrop = assets.imgMenuBarBars.cropping(to: CGRect(x: 24, y: 218, width: assets.imgMenuBarBars.width - 48, height: assets.imgMenuBarBars.height - 244)) ?? assets.imgMenuBarBars
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
            eyebrow: copy.t("02 · ÇIKIŞSIZ ÇİFT PROFİL", "02 · ZERO-LOGOUT DUAL PROFILES"),
            title: copy.t("İki hesapta birden girişli kal", "Stay logged into both accounts"),
            desc: copy.t("İzole --user-data-dir profillerini yerel MCP ayarlarıyla tek tıkla başlatın.", "Launch isolated --user-data-dir profiles with local MCPs & history preserved.")
        )
        let profSlice = assets.winProfilesDark.cropping(to: CGRect(
            x: Int(Double(assets.winProfilesDark.width) * 0.245),
            y: Int(Double(assets.winProfilesDark.height) * 0.235),
            width: Int(Double(assets.winProfilesDark.width) * 0.735),
            height: Int(Double(assets.winProfilesDark.height) * 0.505)
        )) ?? assets.winProfilesDark
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
            eyebrow: copy.t("03 · CANLI LİMİTLER & OTO GEÇİŞ", "03 · REAL-TIME LIMITS & AUTO FAILOVER"),
            title: copy.t("429 veya %95'te otomatik geçiş", "Automatic switch on 429 or 95%"),
            desc: copy.t("Yerel plan-usage-history ve 429 yenilenme sayaçlarını anlık okur.", "Reads local plan-usage-history & 429 resetsAt countdowns in real time.")
        )
        let limSlice = assets.winLimitsDark.cropping(to: CGRect(
            x: Int(Double(assets.winLimitsDark.width) * 0.248),
            y: Int(Double(assets.winLimitsDark.height) * 0.40),
            width: Int(Double(assets.winLimitsDark.width) * 0.73),
            height: Int(Double(assets.winLimitsDark.height) * 0.50)
        )) ?? assets.winLimitsDark
        let limRect = CGRect(x: c3.minX + 28, y: c3.minY + 24, width: c3.width - 56, height: 266)
        fillRoundedRect(cg, rect: limRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let lInner = limRect.insetBy(dx: 12, dy: 12)
        let lAspect = CGFloat(limSlice.width) / CGFloat(limSlice.height)
        let lH = min(lInner.height, lInner.width / lAspect)
        let lW = lH * lAspect
        drawClippedImage(cg, image: limSlice, in: CGRect(x: lInner.midX - lW / 2, y: lInner.midY - lH / 2, width: lW, height: lH), radius: 10, borderColor: Palette.hairlineDark, borderWidth: 1)

        // Card 4: Auto Card Sync & Safety
        drawCardHeader(
            c4,
            eyebrow: copy.t("04 · OTO KART EŞİTLEME & GÜVENLİK", "04 · AUTO SHARED CARD SYNC & SAFETY"),
            title: copy.t("B hesabında çalış. A'da eşit kalsın.", "Work in Account B. Stay synced in A."),
            desc: copy.t("Ortak oturum kartları arka planda sessizce aynalanır — sıfır bulut.", "Shared session cards mirror silently in the background — zero cloud calls.")
        )
        let diagRect = CGRect(x: c4.minX + 28, y: c4.minY + 24, width: c4.width - 56, height: 266)
        fillRoundedRect(cg, rect: diagRect, radius: 14, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)

        let boxW: CGFloat = 178
        let boxH: CGFloat = 94
        let midY = diagRect.minY + 132
        let b1 = CGRect(x: diagRect.minX + 24, y: midY, width: boxW, height: boxH)
        let b2 = CGRect(x: diagRect.midX - boxW / 2, y: midY, width: boxW, height: boxH)
        let b3 = CGRect(x: diagRect.maxX - 24 - boxW, y: midY, width: boxW, height: boxH)

        fillRoundedRect(cg, rect: b1, radius: 12, fill: Palette.cardBg, stroke: Palette.appleGreen.withAlphaComponent(0.45), lineWidth: 1.2)
        drawText(copy.t("1. Hesap", "Account 1"), in: CGRect(x: b1.minX + 12, y: b1.maxY - 34, width: b1.width - 24, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText(copy.t("local_X.json\n142 tur", "local_X.json\n142 turns"), in: CGRect(x: b1.minX + 10, y: b1.minY + 14, width: b1.width - 20, height: 38), font: .monospacedSystemFont(ofSize: 11.5, weight: .medium), color: Palette.textSecondary, alignment: .center)

        fillRoundedRect(cg, rect: b2, radius: 12, fill: Palette.cardElevated, stroke: Palette.terracotta.withAlphaComponent(0.60), lineWidth: 1.4)
        drawText(copy.t("Ortak Transcript", "Shared Transcript"), in: CGRect(x: b2.minX + 8, y: b2.maxY - 34, width: b2.width - 16, height: 22), font: .systemFont(ofSize: 14, weight: .bold), color: Palette.terracotta, alignment: .center)
        drawText("~/.claude/projects/\n<cliId>.jsonl", in: CGRect(x: b2.minX + 8, y: b2.minY + 14, width: b2.width - 16, height: 38), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: Palette.textPrimary, alignment: .center)

        fillRoundedRect(cg, rect: b3, radius: 12, fill: Palette.cardBg, stroke: Palette.appleBlue.withAlphaComponent(0.45), lineWidth: 1.2)
        drawText(copy.t("2. Hesap", "Account 2"), in: CGRect(x: b3.minX + 12, y: b3.maxY - 34, width: b3.width - 24, height: 22), font: .systemFont(ofSize: 15, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText(copy.t("local_X.json\nOto Eşit ✓", "local_X.json\nAuto-Synced ✓"), in: CGRect(x: b3.minX + 10, y: b3.minY + 14, width: b3.width - 20, height: 38), font: .monospacedSystemFont(ofSize: 11.5, weight: .medium), color: Palette.appleGreen, alignment: .center)

        cg.saveGState()
        cg.setStrokeColor(Palette.hairlineStrong.cgColor)
        cg.setLineWidth(1.8)
        cg.move(to: CGPoint(x: b1.maxX + 6, y: b1.midY))
        cg.addLine(to: CGPoint(x: b2.minX - 6, y: b2.midY))
        cg.move(to: CGPoint(x: b2.maxX + 6, y: b2.midY))
        cg.addLine(to: CGPoint(x: b3.minX - 6, y: b3.midY))
        cg.strokePath()
        cg.restoreGState()

        let specY = diagRect.minY + 26
        let specW = (diagRect.width - 48 - 20) / 3
        let specs: [(String, String)] = copy.lang.isTurkish ? [
            ("Sıfır Şifre/Token", "Çerez veya Keychain okumaz"),
            ("Otomatik Yedek", "Yazmadan önce zaman damgalı"),
            ("Atomik 0600", "Bulut bridgeSessionIds temizler")
        ] : [
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

    try savePNG(rep, to: outURL)
    if let docsCopyURL { try savePNG(rep, to: docsCopyURL) }
}

// MARK: - Visual 3: Architecture Diagram (1600×900)

func generateArchitectureVisual(copy: KitCopy, outURL: URL, docsCopyURL: URL?) throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 36, alpha: 0.04)

        drawPill(cg, text: copy.t("CLAUDESYNC ARKA PLANDA NASIL ÇALIŞIR?", "HOW CLAUDESYNC WORKS UNDER THE HOOD"), centerX: size.width / 2, y: 822, height: 28, textColor: Palette.terracotta, fontSize: 11)
        drawText(
            copy.t("Tamamen yerel mimari. Sıfır cookie/token müdahalesi.", "Local-first architecture. Zero credential hacks."),
            in: CGRect(x: 80, y: 748, width: 1440, height: 56),
            font: .systemFont(ofSize: 42, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.0
        )
        drawText(
            copy.t(
                "Claude Desktop sohbet kayıtlarını diskte zaten ortak tutar. ClaudeSYNC hesap bazlı yan menü kartlarını güvenle köprüler.",
                "Claude Desktop already shares conversation transcripts on disk. ClaudeSYNC safely bridges the per-account index cards."
            ),
            in: CGRect(x: 160, y: 706, width: 1280, height: 30),
            font: .systemFont(ofSize: 17, weight: .regular),
            color: Palette.textSecondary,
            alignment: .center
        )

        let colW: CGFloat = 440
        let colH: CGFloat = 460
        let colY: CGFloat = 176
        let gap: CGFloat = 60
        let startX = (size.width - (colW * 3 + gap * 2)) / 2

        let leftCol = CGRect(x: startX, y: colY, width: colW, height: colH)
        let midCol = CGRect(x: startX + colW + gap, y: colY, width: colW, height: colH)
        let rightCol = CGRect(x: startX + (colW + gap) * 2, y: colY, width: colW, height: colH)

        // Left
        fillRoundedRect(cg, rect: leftCol, radius: 18, fill: Palette.cardBg, stroke: Palette.appleGreen.withAlphaComponent(0.35), lineWidth: 1.2)
        drawText(copy.t("1. PROFİL · HESAP A", "PROFILE 1 · ACCOUNT A"), in: CGRect(x: leftCol.minX + 26, y: leftCol.maxY - 42, width: colW - 52, height: 18), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.appleGreen, kern: 1.0)
        drawText(copy.t("Claude Desktop (Ana Profil)", "Claude Desktop (Primary)"), in: CGRect(x: leftCol.minX + 26, y: leftCol.maxY - 76, width: colW - 52, height: 28), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.textPrimary)

        let leftBoxes: [(String, String, String)] = copy.lang.isTurkish ? [
            ("Oturum İndeks Kartları", "~/Library/Application Support/Claude/\nclaude-code-sessions/<acc1>/<org1>/", "local_*.json"),
            ("Kullanım Telemetrisi", "plan-usage-history.json", "5s / 7g / xu"),
            ("Canlı Süreç Algılama", "claude --resume=<cliSessionId>", "Aktif PID")
        ] : [
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

        // Center
        fillRoundedRect(cg, rect: midCol, radius: 18, fill: Palette.cardElevated, stroke: Palette.terracotta.withAlphaComponent(0.55), lineWidth: 1.5)
        drawClaudeSyncIcon(cg, rect: CGRect(x: midCol.midX - 24, y: midCol.maxY - 72, width: 48, height: 48))
        drawText(copy.t("ClaudeSYNC Motoru", "ClaudeSYNC Engine"), in: CGRect(x: midCol.minX + 20, y: midCol.maxY - 114, width: colW - 40, height: 30), font: .systemFont(ofSize: 23, weight: .bold), color: Palette.textPrimary, alignment: .center)
        drawText(copy.t("Saf Swift · Yalnızca Yerel Dosya Sistemi", "Pure Swift · Local Filesystem Only"), in: CGRect(x: midCol.minX + 20, y: midCol.maxY - 138, width: colW - 40, height: 20), font: .systemFont(ofSize: 13, weight: .medium), color: Palette.terracotta, alignment: .center)

        let steps: [(String, String)] = copy.lang.isTurkish ? [
            ("1. Ortak Transcript Doğrulama", "~/.claude/projects/<cliId>.jsonl diskte doğrulanır"),
            ("2. Hesaplar Arası Temizlik", "bridgeSessionIds & remoteMcpServersConfig temizler"),
            ("3. Atomik Yedek & Yazım", "Zaman damgalı yedek + atomik 0600 JSON yazım"),
            ("4. Oto Kart Aynalama & Failover", "Ortak kartları eşitler + 429'da otomatik geçer")
        ] : [
            ("1. Shared Transcript Verification", "Confirms ~/.claude/projects/<cliId>.jsonl on disk"),
            ("2. Cross-Account Hygiene", "Strips bridgeSessionIds & remoteMcpServersConfig"),
            ("3. Atomic Backup & Write", "Timestamped backup + atomic 0600 JSON write"),
            ("4. Auto Card Mirror & Failover", "Keeps shared cards equal + switches on 429")
        ]
        for (i, step) in steps.enumerated() {
            let r = CGRect(x: midCol.minX + 24, y: midCol.maxY - 224 - CGFloat(i) * 74, width: colW - 48, height: 62)
            fillRoundedRect(cg, rect: r, radius: 10, fill: Palette.canvasBg, stroke: Palette.hairlineDark, lineWidth: 1)
            drawText(step.0, in: CGRect(x: r.minX + 14, y: r.maxY - 27, width: r.width - 28, height: 18), font: .systemFont(ofSize: 13, weight: .semibold), color: Palette.textPrimary)
            drawText(step.1, in: CGRect(x: r.minX + 14, y: r.minY + 10, width: r.width - 28, height: 18), font: .systemFont(ofSize: 11.2, weight: .regular), color: Palette.textSecondary)
        }

        // Right
        fillRoundedRect(cg, rect: rightCol, radius: 18, fill: Palette.cardBg, stroke: Palette.appleBlue.withAlphaComponent(0.35), lineWidth: 1.2)
        drawText(copy.t("2. PROFİL · HESAP B", "PROFILE 2 · ACCOUNT B"), in: CGRect(x: rightCol.minX + 26, y: rightCol.maxY - 42, width: colW - 52, height: 18), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.appleBlue, kern: 1.0)
        drawText(copy.t("Claude Desktop (İzole Profil)", "Claude Desktop (Isolated)"), in: CGRect(x: rightCol.minX + 26, y: rightCol.maxY - 76, width: colW - 52, height: 28), font: .systemFont(ofSize: 22, weight: .bold), color: Palette.textPrimary)

        let rightBoxes: [(String, String, String)] = copy.lang.isTurkish ? [
            ("İzole --user-data-dir", "~/Library/Application Support/\nClaude-Account2/", "Çıkışsız"),
            ("Eşitlenen Yan Menü Kartları", "Tam sohbet bağlamıyla en üstte\nanında kaldığın yerden devam", "Oto Aynalama"),
            ("Ortak Transcript Katmanı", "~/.claude/projects/*/*.jsonl\nÇift kopya yok, tek gerçek kaynak", "Ortak Disk")
        ] : [
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

        // Connectors
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

        let footerRect = CGRect(x: startX, y: 66, width: size.width - startX * 2, height: 68)
        fillRoundedRect(cg, rect: footerRect, radius: 14, fill: Palette.cardBg, stroke: Palette.hairlineDark, lineWidth: 1)
        let footerItems = copy.lang.isTurkish ? [
            "Native SwiftUI + AppKit",
            "Sıfır Electron (1.3 MB DMG)",
            "Sıfır Ağ / Sıfır Telemetri",
            "github.com/berkayildize/ClaudeSYNC"
        ] : [
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

    try savePNG(rep, to: outURL)
    if let docsCopyURL { try savePNG(rep, to: docsCopyURL) }
}

// MARK: - Visual 4: Dark & Light Split Showcase (1600×900)

func generateDarkLightShowcase(copy: KitCopy, assets: LangAssets, outURL: URL, docsCopyURL: URL?) throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
        cg.setFillColor(Palette.lightBg.cgColor)
        cg.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))

        cg.setFillColor(NSColor.gray.withAlphaComponent(0.25).cgColor)
        cg.fill(CGRect(x: size.width / 2 - 0.5, y: 0, width: 1, height: size.height))

        drawText(copy.t("KOYU TEMA", "DARK MODE"), in: CGRect(x: 56, y: 824, width: 320, height: 22), font: .systemFont(ofSize: 12, weight: .bold), color: Palette.terracotta, kern: 1.4)
        drawText(copy.t("Native macOS Cam Tasarım.", "Native macOS Glass."), in: CGRect(x: 56, y: 774, width: 680, height: 46), font: .systemFont(ofSize: 38, weight: .bold), color: Palette.textPrimary, kern: -0.9)

        drawText(copy.t("AÇIK TEMA", "LIGHT MODE"), in: CGRect(x: size.width / 2 + 56, y: 824, width: 320, height: 22), font: .systemFont(ofSize: 12, weight: .bold), color: Palette.terracotta, kern: 1.4)
        drawText(copy.t("120Hz Akıcılık. Sıfır Gradyan.", "120Hz ProMotion. Zero Gradients."), in: CGRect(x: size.width / 2 + 56, y: 774, width: 700, height: 46), font: .systemFont(ofSize: 38, weight: .bold), color: NSColor(calibratedWhite: 0.11, alpha: 1.0), kern: -0.9)

        let cardW: CGFloat = 716
        let cardH: CGFloat = cardW * (CGFloat(assets.winMainDark.height) / CGFloat(assets.winMainDark.width))
        let yPos: CGFloat = (736 - cardH) / 2 + 12

        let leftRect = CGRect(x: (size.width / 2 - cardW) / 2, y: yPos, width: cardW, height: cardH)
        let rightRect = CGRect(x: size.width / 2 + (size.width / 2 - cardW) / 2, y: yPos, width: cardW, height: cardH)

        drawClippedImage(cg, image: assets.winMainDark, in: leftRect, radius: 15, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        drawClippedImage(cg, image: assets.winMainLight, in: rightRect, radius: 15, borderColor: NSColor.black.withAlphaComponent(0.14), borderWidth: 1.5)

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

    try savePNG(rep, to: outURL)
    if let docsCopyURL { try savePNG(rep, to: docsCopyURL) }
}

// MARK: - Visual 5: First-Launch Setup Wizard & Permissions Showcase (1600×900)

func generateOnboardingShowcase(copy: KitCopy, assets: LangAssets, outURL: URL, docsCopyURL: URL?) throws {
    let rep = withCanvas(width: 1600, height: 900) { cg, size in
        cg.setFillColor(Palette.canvasBg.cgColor)
        cg.fill(CGRect(origin: .zero, size: size))
        drawSubtleDotGrid(cg, size: size, step: 36, alpha: 0.04)

        drawPill(cg, text: copy.t("İLK KURULUM SİHİRBAZI · TR & EN", "FIRST-LAUNCH SETUP WIZARD · EN & TR"), centerX: size.width / 2, y: 828, height: 28, textColor: Palette.terracotta, fontSize: 11)
        drawText(
            copy.t("60 saniyede kurulum. Şeffaf izin kontrolü.", "Ready in 60 seconds. Zero invasive permissions."),
            in: CGRect(x: 100, y: 754, width: 1400, height: 56),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )
        drawText(
            copy.t(
                "DMG'yi açtığınız anda dil seçimi, Claude Desktop klasör doğrulaması, bildirim izni ve 2. profil kurulumu adım adım hazır.",
                "Pick English or Turkish on first launch, verify local Claude folders & notifications, and configure dual profiles step by step."
            ),
            in: CGRect(x: 160, y: 712, width: 1280, height: 30),
            font: .systemFont(ofSize: 17, weight: .regular),
            color: Palette.textSecondary,
            alignment: .center
        )

        // Two clean symmetric macOS windows side-by-side: Step 1 (Language) & Step 2 (System & Permissions)
        let padX: CGFloat = 56
        let gap: CGFloat = 28
        let winW: CGFloat = (size.width - padX * 2 - gap) / 2
        let winH: CGFloat = winW * (CGFloat(assets.winOnboardingWelcome.height) / CGFloat(assets.winOnboardingWelcome.width))
        let yPos: CGFloat = 112

        let leftRect = CGRect(x: padX, y: yPos, width: winW, height: winH)
        let rightRect = CGRect(x: padX + winW + gap, y: yPos, width: winW, height: winH)

        drawText(copy.t("ADIM 1 · CANLI DİL SEÇİMİ (TR / EN / SİSTEM)", "STEP 1 · LIVE LANGUAGE PICKER (EN / TR / AUTO)"), in: CGRect(x: leftRect.minX, y: leftRect.maxY + 12, width: winW, height: 20), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.textSecondary, alignment: .center, kern: 0.8)
        drawText(copy.t("ADIM 2 · SİSTEM & İZİN DOĞRULAMA", "STEP 2 · ENVIRONMENT & PERMISSIONS CHECK"), in: CGRect(x: rightRect.minX, y: rightRect.maxY + 12, width: winW, height: 20), font: .systemFont(ofSize: 11, weight: .bold), color: Palette.textSecondary, alignment: .center, kern: 0.8)

        drawClippedImage(cg, image: assets.winOnboardingWelcome, in: leftRect, radius: 14, borderColor: Palette.hairlineStrong, borderWidth: 1.4)
        drawClippedImage(cg, image: assets.winOnboardingPerms, in: rightRect, radius: 14, borderColor: Palette.hairlineStrong, borderWidth: 1.4)

        drawPill(
            cg,
            text: copy.t("Erişilebilirlik Yok · Ekran Kaydı Yok · Keychain Erişimi Yok", "No Accessibility · No Screen Recording · No Keychain Access"),
            centerX: size.width / 2,
            y: 44,
            height: 34,
            fill: Palette.cardBg,
            border: Palette.appleGreen.withAlphaComponent(0.38),
            textColor: Palette.appleGreen,
            fontSize: 12
        )
    }

    try savePNG(rep, to: outURL)
    if let docsCopyURL { try savePNG(rep, to: docsCopyURL) }
}

// MARK: - 1080p60 Bilingual Launch Promo Video (25s, 1500 Frames, 7 Scenes)

func easeOutCubic(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return 1.0 - pow(1.0 - x, 3.0)
}

func easeInOutCubic(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

func clamp01(_ v: Double) -> Double { min(max(v, 0), 1) }

func drawVideoFrame(cg: CGContext, time: Double, copy: KitCopy, assets: LangAssets) {
    let w: CGFloat = 1920
    let h: CGFloat = 1080
    let size = CGSize(width: w, height: h)
    let totalDuration = 25.0

    cg.setFillColor(Palette.canvasBg.cgColor)
    cg.fill(CGRect(origin: .zero, size: size))
    drawSubtleDotGrid(cg, size: size, step: 40, alpha: 0.036)

    // Bottom thin terracotta timeline rail
    let progress = CGFloat(clamp01(time / totalDuration))
    cg.setFillColor(NSColor.white.withAlphaComponent(0.08).cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: w, height: 3))
    cg.setFillColor(Palette.terracotta.cgColor)
    cg.fill(CGRect(x: 0, y: 0, width: w * progress, height: 3))

    func sceneAlpha(start: Double, end: Double, fadeIn: Double = 0.45, fadeOut: Double = 0.40) -> Double {
        let aIn = easeOutCubic((time - start) / fadeIn)
        let aOut = 1.0 - easeInOutCubic((time - (end - fadeOut)) / fadeOut)
        return clamp01(min(aIn, aOut))
    }

    // SCENE 1 (0.0s – 3.5s): Hook & Brand Reveal
    if time < 3.7 {
        let a = sceneAlpha(start: 0.0, end: 3.5, fadeIn: 0.45, fadeOut: 0.40)
        let pIcon = easeOutCubic(time / 0.7)
        let pLine1 = easeOutCubic((time - 0.3) / 0.6)
        let pLine2 = easeOutCubic((time - 0.65) / 0.6)
        let pSub = easeOutCubic((time - 1.0) / 0.6)

        cg.saveGState()
        cg.setAlpha(a)

        let iconSz: CGFloat = 88 * (0.86 + 0.14 * CGFloat(pIcon))
        drawClaudeSyncIcon(cg, rect: CGRect(x: (w - iconSz) / 2, y: 690 - (1 - CGFloat(pIcon)) * 18, width: iconSz, height: iconSz))

        cg.saveGState()
        cg.setAlpha(a * pLine1)
        drawText(
            copy.t("Claude limiti mi doldu?", "Hit a Claude rate limit?"),
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
            copy.t("Aynı oturumdan devam et.", "Keep your exact session."),
            in: CGRect(x: 160, y: 472 - (1 - CGFloat(pLine2)) * 22, width: w - 320, height: 84),
            font: .systemFont(ofSize: 72, weight: .bold),
            color: Palette.terracotta,
            alignment: .center,
            kern: -1.8
        )
        cg.restoreGState()

        cg.saveGState()
        cg.setAlpha(a * pSub)
        drawPill(
            cg,
            text: copy.t("MACOS İÇİN CLAUDESYNC · AÇIK KAYNAK · TR & EN", "INTRODUCING CLAUDESYNC FOR MACOS · OPEN SOURCE · EN & TR"),
            centerX: w / 2,
            y: 382 - (1 - CGFloat(pSub)) * 12,
            height: 38,
            fontSize: 13
        )
        cg.restoreGState()
        cg.restoreGState()
    }

    // SCENE 2 (3.2s – 6.9s): First-Launch Setup Wizard & Permissions
    if time >= 3.1 && time < 7.1 {
        let local = time - 3.2
        let a = sceneAlpha(start: 3.2, end: 6.9, fadeIn: 0.45, fadeOut: 0.40)
        let enter = easeOutCubic(local / 0.75)

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: copy.t("01 · İLK KURULUM SİHİRBAZI & İZİN KONTROLÜ", "01 · GUIDED SETUP WIZARD & PERMISSIONS"), centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            copy.t("Türkçe & İngilizce. Şeffaf yerel izin doğrulaması.", "Bilingual EN & TR. Zero invasive permissions."),
            in: CGRect(x: 120, y: 908, width: w - 240, height: 60),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )

        let baseW: CGFloat = 1120 * (0.97 + 0.03 * CGFloat(enter))
        let baseH: CGFloat = baseW * (CGFloat(assets.winOnboardingPerms.height) / CGFloat(assets.winOnboardingPerms.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 36, width: baseW, height: baseH)
        drawClippedImage(cg, image: assets.winOnboardingPerms, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // SCENE 3 (6.6s – 10.7s): Full Desktop App (Sessions Workspace)
    if time >= 6.5 && time < 10.9 {
        let local = time - 6.6
        let a = sceneAlpha(start: 6.6, end: 10.7, fadeIn: 0.45, fadeOut: 0.40)
        let enter = easeOutCubic(local / 0.80)
        let slowScale = 0.96 + 0.04 * CGFloat(enter) + 0.012 * CGFloat(clamp01(local / 4.1))

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: copy.t("02 · NATIVE MACOS MASAÜSTÜ UYGULAMASI", "02 · NATIVE MACOS DESKTOP APP"), centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            copy.t("Tüm oturumlar iki hesap arasında anlık eşit.", "Every session, synced across both accounts."),
            in: CGRect(x: 140, y: 908, width: w - 280, height: 60),
            font: .systemFont(ofSize: 46, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.2
        )

        let baseW: CGFloat = 1120 * slowScale
        let baseH: CGFloat = baseW * (CGFloat(assets.winMainDark.height) / CGFloat(assets.winMainDark.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 42, width: baseW, height: baseH)
        drawClippedImage(cg, image: assets.winMainDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // SCENE 4 (10.4s – 14.3s): Live Limits & Auto-Failover
    if time >= 10.3 && time < 14.5 {
        let local = time - 10.4
        let a = sceneAlpha(start: 10.4, end: 14.3, fadeIn: 0.45, fadeOut: 0.40)
        let enter = easeOutCubic(local / 0.75)
        let drift = CGFloat(clamp01(local / 3.9))

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: copy.t("03 · CANLI LİMİTLER & OTOMATİK GEÇİŞ", "03 · REAL-TIME LIMITS & AUTO FAILOVER"), centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            copy.t("Canlı 5s / 7g göstergeleri, geri sayım ve 429'da oto geçiş.", "Live 5h / 7d gauges, reset countdowns, automatic switch on 429."),
            in: CGRect(x: 100, y: 908, width: w - 200, height: 60),
            font: .systemFont(ofSize: 41, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.0
        )

        let baseW: CGFloat = 1120 * (0.97 + 0.03 * CGFloat(enter) + 0.015 * drift)
        let baseH: CGFloat = baseW * (CGFloat(assets.winLimitsDark.height) / CGFloat(assets.winLimitsDark.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 36, width: baseW, height: baseH)
        drawClippedImage(cg, image: assets.winLimitsDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // SCENE 5 (14.0s – 17.7s): Zero-Logout Dual Profiles
    if time >= 13.9 && time < 17.9 {
        let local = time - 14.0
        let a = sceneAlpha(start: 14.0, end: 17.7, fadeIn: 0.45, fadeOut: 0.40)
        let enter = easeOutCubic(local / 0.75)

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: copy.t("04 · ÇIKIŞSIZ ÇİFT PROFİL (--user-data-dir)", "04 · ZERO-LOGOUT DUAL PROFILES (--user-data-dir)"), centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            copy.t("İki Ultra hesapta birden girişli kal. Tek tıkla geç.", "Stay signed into both Ultra accounts. Switch in one click."),
            in: CGRect(x: 120, y: 908, width: w - 240, height: 60),
            font: .systemFont(ofSize: 44, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )

        let baseW: CGFloat = 1120 * (0.97 + 0.03 * CGFloat(enter))
        let baseH: CGFloat = baseW * (CGFloat(assets.winProfilesDark.height) / CGFloat(assets.winProfilesDark.width))
        let rect = CGRect(x: (w - baseW) / 2, y: 868 - baseH - (1 - CGFloat(enter)) * 36, width: baseW, height: baseH)
        drawClippedImage(cg, image: assets.winProfilesDark, in: rect, radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // SCENE 6 (17.4s – 21.4s): Retina Menu Bar Bars + Light Mode
    if time >= 17.3 && time < 21.6 {
        let local = time - 17.4
        let a = sceneAlpha(start: 17.4, end: 21.4, fadeIn: 0.45, fadeOut: 0.40)
        let enter = easeOutCubic(local / 0.75)

        cg.saveGState()
        cg.setAlpha(a)

        drawPill(cg, text: copy.t("05 · RETİNA ÜST BAR & AÇIK TEMA", "05 · RETINA MENU BAR BARS & LIGHT MODE"), centerX: w / 2, y: 982, height: 30, textColor: Palette.terracotta, fontSize: 12)
        drawText(
            copy.t("Üst barda canlı limit barları. İstediğin an aç veya kapat.", "Glanceable top-bar limits. Toggle menu bar ON or OFF anytime."),
            in: CGRect(x: 120, y: 908, width: w - 240, height: 60),
            font: .systemFont(ofSize: 43, weight: .bold),
            color: Palette.textPrimary,
            alignment: .center,
            kern: -1.1
        )

        let yBase: CGFloat = 148 - (1 - CGFloat(enter)) * 30
        let leftCard = CGRect(x: 110, y: yBase, width: 740, height: 700)
        let rightCard = CGRect(x: 890, y: yBase, width: 920, height: 700)

        fillRoundedRect(cg, rect: leftCard, radius: 18, fill: Palette.cardBg, stroke: Palette.hairlineStrong, lineWidth: 1.2)
        let mbAspect = CGFloat(assets.imgMenuBarBars.width) / CGFloat(assets.imgMenuBarBars.height)
        let mbW = leftCard.width - 56
        let mbH = mbW / mbAspect
        drawClippedImage(cg, image: assets.imgMenuBarBars, in: CGRect(x: leftCard.midX - mbW / 2, y: leftCard.midY - mbH / 2, width: mbW, height: mbH), radius: 14)

        let lAspect = CGFloat(assets.winMainLight.width) / CGFloat(assets.winMainLight.height)
        let lW = rightCard.width
        let lH = lW / lAspect
        drawClippedImage(cg, image: assets.winMainLight, in: CGRect(x: rightCard.minX, y: rightCard.midY - lH / 2, width: lW, height: lH), radius: 18, borderColor: Palette.hairlineStrong, borderWidth: 1.5)
        cg.restoreGState()
    }

    // SCENE 7 (21.1s – 25.0s): Outro CTA
    if time >= 21.0 {
        let local = time - 21.1
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
            copy.t("%100 Yerel · Sıfır Telemetri · MIT Açık Kaynak", "100% Local · Zero Telemetry · MIT Open Source"),
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
            copy.t("macOS 14+ · Native SwiftUI & AppKit · Türkçe & English · 1.3 MB DMG", "macOS 14+ · Native SwiftUI & AppKit · English & Turkish · 1.3 MB DMG"),
            in: CGRect(x: 120, y: 316 - rise, width: w - 240, height: 28),
            font: .monospacedSystemFont(ofSize: 15, weight: .medium),
            color: Palette.textTertiary,
            alignment: .center
        )

        cg.restoreGState()
    }
}

func generateLaunchVideo(copy: KitCopy, assets: LangAssets, mp4URL: URL, keyframesDir: URL) throws {
    try? FileManager.default.removeItem(at: mp4URL)
    try FileManager.default.createDirectory(at: keyframesDir, withIntermediateDirectories: true)

    let width = 1920
    let height = 1080
    let fps: Int32 = 60
    let durationSec = 25.0
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
        Int(1.8 * 60): "kf-01-hook.png",
        Int(5.0 * 60): "kf-02-onboarding.png",
        Int(8.6 * 60): "kf-03-app.png",
        Int(12.3 * 60): "kf-04-limits.png",
        Int(15.8 * 60): "kf-05-profiles.png",
        Int(19.4 * 60): "kf-06-menubar-light.png",
        Int(23.2 * 60): "kf-07-outro.png"
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
            drawVideoFrame(cg: cg, time: t, copy: copy, assets: assets)

            NSGraphicsContext.restoreGraphicsState()

            if let kfName = keyframeTimes[frameIdx], let cgSnap = cg.makeImage() {
                let rep = NSBitmapImageRep(cgImage: cgSnap)
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: keyframesDir.appendingPathComponent(kfName))
                }
            }

            let pts = CMTime(value: CMTimeValue(frameIdx), timescale: fps)
            adaptor.append(pb, withPresentationTime: pts)
        }
    }

    input.markAsFinished()
    let sem = DispatchSemaphore(value: 0)
    writer.finishWriting { sem.signal() }
    sem.wait()

    if writer.status != .completed {
        fatalError("AVAssetWriter failed: \(String(describing: writer.error))")
    }
    print("Saved \(mp4URL.path) (1920x1080 @ 60fps, \(totalFrames) frames)")
}

// MARK: - Main Entry Point

let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
let docsAssetsURL = rootURL.appendingPathComponent("docs/assets", isDirectory: true)
let launchKitURL = rootURL.appendingPathComponent("launch-kit", isDirectory: true)

let args = CommandLine.arguments
let visualsOnly = args.contains("--visuals-only")
let langsToBuild: [KitLang] = {
    if args.contains("--lang=en") { return [.en] }
    if args.contains("--lang=tr") { return [.tr] }
    return [.en, .tr]
}()

for lang in langsToBuild {
    let copy = KitCopy(lang: lang)
    let rawDir = (lang == .en)
        ? docsAssetsURL
        : launchKitURL.appendingPathComponent("tr/raw", isDirectory: true)
    let langOut = launchKitURL.appendingPathComponent(lang.rawValue, isDirectory: true)
    let visualsDir = langOut.appendingPathComponent("visuals", isDirectory: true)
    let videoDir = langOut.appendingPathComponent("video", isDirectory: true)
    let keyframesDir = videoDir.appendingPathComponent("keyframes", isDirectory: true)

    try FileManager.default.createDirectory(at: visualsDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)

    print("==> [\(lang.upper)] Loading Retina UI snapshots from \(rawDir.path)...")
    let assets = LangAssets.load(from: rawDir)

    let isEN = (lang == .en)
    print("==> [\(lang.upper)] Generating 5 Launch Visuals...")
    try generateHeroBanner(
        copy: copy,
        assets: assets,
        outURL: visualsDir.appendingPathComponent("01-hero-banner-\(lang.suffix).png"),
        docsCopyURL: isEN ? docsAssetsURL.appendingPathComponent("hero-banner.png") : nil
    )
    try generateFeatureBento(
        copy: copy,
        assets: assets,
        outURL: visualsDir.appendingPathComponent("02-bento-features-\(lang.suffix).png"),
        docsCopyURL: isEN ? docsAssetsURL.appendingPathComponent("features-bento.png") : nil
    )
    try generateArchitectureVisual(
        copy: copy,
        outURL: visualsDir.appendingPathComponent("03-architecture-\(lang.suffix).png"),
        docsCopyURL: isEN ? docsAssetsURL.appendingPathComponent("architecture.png") : nil
    )
    try generateDarkLightShowcase(
        copy: copy,
        assets: assets,
        outURL: visualsDir.appendingPathComponent("04-dark-light-split-\(lang.suffix).png"),
        docsCopyURL: isEN ? docsAssetsURL.appendingPathComponent("dark-light-split.png") : nil
    )
    try generateOnboardingShowcase(
        copy: copy,
        assets: assets,
        outURL: visualsDir.appendingPathComponent("05-onboarding-\(lang.suffix).png"),
        docsCopyURL: isEN ? docsAssetsURL.appendingPathComponent("onboarding-showcase.png") : nil
    )

    if !visualsOnly {
        print("==> [\(lang.upper)] Rendering 1080p60 Launch Video...")
        try generateLaunchVideo(
            copy: copy,
            assets: assets,
            mp4URL: videoDir.appendingPathComponent("ClaudeSYNC-Launch-\(lang.upper)-1080p60.mp4"),
            keyframesDir: keyframesDir
        )
    }
}

print("==> Bilingual Launch Kit (EN + TR) complete!")
