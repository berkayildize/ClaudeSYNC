import AppKit
import ClaudeSYNCCore
import Foundation

struct MenuBarRenderKey: Equatable {
    let mode: MenuBarDisplayMode
    let isDark: Bool
    let topPercent: Int?
    let bottomPercent: Int?
    let topLabel: String?
    let bottomLabel: String?
    let isSwitching: Bool
}

@MainActor
final class MenuBarWidgetRenderer {
    static let shared = MenuBarWidgetRenderer()

    private var cachedKey: MenuBarRenderKey?
    private var cachedImage: NSImage?

    func image(
        mode: MenuBarDisplayMode,
        accounts: [AccountSlot],
        activeAccount: AccountSlot?,
        isSwitching: Bool,
        overrideDark: Bool? = nil
    ) -> NSImage {
        let isDark: Bool
        if let overrideDark {
            isDark = overrideDark
        } else {
            let match = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
            isDark = (match == .darkAqua)
        }

        let topPct: Int?
        let botPct: Int?
        let topLbl: String?
        let botLbl: String?

        switch mode {
        case .iconOnly:
            topPct = nil
            botPct = nil
            topLbl = nil
            botLbl = nil
        case .iconAndBothAccounts:
            let primary = activeAccount ?? accounts.first
            let secondary = accounts.first { $0.id != primary?.id }
            topPct = primary?.usage?.peakPercent
            botPct = secondary?.usage?.peakPercent
            topLbl = nil
            botLbl = nil
        case .iconAndActiveUsage:
            let primary = activeAccount ?? accounts.first
            topPct = primary?.usage?.fiveHourPercent
            botPct = primary?.usage?.sevenDayPercent
            topLbl = "5s"
            botLbl = "7g"
        }

        let key = MenuBarRenderKey(
            mode: mode,
            isDark: isDark,
            topPercent: topPct,
            bottomPercent: botPct,
            topLabel: topLbl,
            bottomLabel: botLbl,
            isSwitching: isSwitching
        )

        if let cachedKey, cachedKey == key, let cachedImage {
            return cachedImage
        }

        let img = Self.renderImage(for: key)
        cachedKey = key
        cachedImage = img
        return img
    }

    static func renderImage(for key: MenuBarRenderKey) -> NSImage {
        let scale: CGFloat = 2.0
        let height: CGFloat = 22.0

        let showBars = (key.mode != .iconOnly) && (key.topPercent != nil || key.bottomPercent != nil)
        let hasTextPrefix = (key.topLabel != nil || key.bottomLabel != nil)
        let width: CGFloat = showBars ? (hasTextPrefix ? 104.0 : 94.0) : 20.0

        let pixW = Int(width * scale)
        let pixH = Int(height * scale)

        guard let rep = NSBitmapImageRep(
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
        ) else {
            return NSImage(size: NSSize(width: width, height: height))
        }
        rep.size = NSSize(width: width, height: height)

        NSGraphicsContext.saveGraphicsState()
        if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
            NSGraphicsContext.current = ctx
            ctx.imageInterpolation = .high
            let cg = ctx.cgContext

            let fgColor = key.isDark ? NSColor.white : NSColor(calibratedWhite: 0.10, alpha: 1.0)
            let badgeBg = key.isDark ? NSColor.white : NSColor(calibratedWhite: 0.14, alpha: 1.0)
            let badgeArrow = key.isDark
                ? NSColor(calibratedWhite: 0.10, alpha: 1.0)
                : NSColor.white

            // 1. Custom ClaudeSYNC Vector Emblem (Claude starburst + corner transfer badge)
            let emblemRect = CGRect(x: 1.0, y: 2.5, width: 17.0, height: 17.0)
            ClaudeSyncVectorArt.drawMenuBarEmblem(
                in: cg,
                rect: emblemRect,
                starburstColor: ClaudeSyncVectorArt.claudeTerracottaNS.cgColor,
                badgeBgColor: badgeBg.cgColor,
                arrowColor: badgeArrow.cgColor,
                cutoutColor: nil
            )

            // 2. Stacked Crisp Retina Micro-Bars
            if showBars {
                let startX: CGFloat = 22.5
                drawBarRow(
                    in: cg,
                    startX: startX,
                    centerY: 15.0,
                    prefixLabel: key.topLabel,
                    isActiveRow: true,
                    percent: key.topPercent,
                    fgColor: fgColor,
                    isDark: key.isDark
                )
                drawBarRow(
                    in: cg,
                    startX: startX,
                    centerY: 7.0,
                    prefixLabel: key.bottomLabel,
                    isActiveRow: false,
                    percent: key.bottomPercent,
                    fgColor: fgColor,
                    isDark: key.isDark
                )
            }
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: NSSize(width: width, height: height))
        image.addRepresentation(rep)
        image.isTemplate = false
        return image
    }

    private static func drawBarRow(
        in cg: CGContext,
        startX: CGFloat,
        centerY: CGFloat,
        prefixLabel: String?,
        isActiveRow: Bool,
        percent: Int?,
        fgColor: NSColor,
        isDark: Bool
    ) {
        let barX: CGFloat
        if let prefix = prefixLabel {
            let prefixFont = NSFont.systemFont(ofSize: 7.5, weight: .semibold)
            let prefixAttrs: [NSAttributedString.Key: Any] = [
                .font: prefixFont,
                .foregroundColor: fgColor.withAlphaComponent(isActiveRow ? 0.85 : 0.62)
            ]
            let s = NSAttributedString(string: prefix, attributes: prefixAttrs)
            s.draw(at: NSPoint(x: startX, y: centerY - 5.0))
            barX = startX + 13.0
        } else {
            // Subtle status dot: bright active indicator for row 1, muted dot for row 2
            let dotSize: CGFloat = 3.5
            let dotColor: NSColor = {
                if let p = percent {
                    return isActiveRow ? usageNSColor(percent: p) : fgColor.withAlphaComponent(0.38)
                }
                return fgColor.withAlphaComponent(0.25)
            }()
            cg.setFillColor(dotColor.cgColor)
            cg.fillEllipse(in: CGRect(
                x: startX,
                y: centerY - dotSize / 2.0,
                width: dotSize,
                height: dotSize
            ))
            barX = startX + 6.5
        }

        // Pill track
        let barW: CGFloat = 38.0
        let barH: CGFloat = 4.6
        let barRect = CGRect(x: barX, y: centerY - barH / 2.0, width: barW, height: barH)
        let trackPath = CGPath(roundedRect: barRect, cornerWidth: barH / 2.0, cornerHeight: barH / 2.0, transform: nil)

        cg.setFillColor(fgColor.withAlphaComponent(isDark ? 0.19 : 0.14).cgColor)
        cg.addPath(trackPath)
        cg.fillPath()

        cg.setStrokeColor(fgColor.withAlphaComponent(isDark ? 0.16 : 0.14).cgColor)
        cg.setLineWidth(0.5)
        cg.addPath(trackPath)
        cg.strokePath()

        // Solid flat Apple fill (zero gradients)
        if let p = percent, p > 0 {
            let clamped = CGFloat(min(max(p, 0), 100)) / 100.0
            let fillW = max(barH, barW * clamped)
            let fillRect = CGRect(x: barX, y: centerY - barH / 2.0, width: fillW, height: barH)
            let fillPath = CGPath(roundedRect: fillRect, cornerWidth: barH / 2.0, cornerHeight: barH / 2.0, transform: nil)
            cg.setFillColor(usageNSColor(percent: p).cgColor)
            cg.addPath(fillPath)
            cg.fillPath()
        }

        // Crisp right-aligned tabular percentage text
        let pctStr = percent.map { "\($0)%" } ?? "—"
        let pctFont = NSFont.monospacedDigitSystemFont(
            ofSize: 8.5,
            weight: isActiveRow ? .semibold : .medium
        )
        let pctColor: NSColor = {
            if let p = percent, p >= 95 {
                return usageNSColor(percent: p)
            }
            return fgColor.withAlphaComponent(isActiveRow ? 0.96 : 0.72)
        }()

        let para = NSMutableParagraphStyle()
        para.alignment = .right
        let pctAttrs: [NSAttributedString.Key: Any] = [
            .font: pctFont,
            .foregroundColor: pctColor,
            .paragraphStyle: para
        ]
        let textRect = NSRect(x: barX + barW + 2.5, y: centerY - 5.6, width: 25.5, height: 11.0)
        NSAttributedString(string: pctStr, attributes: pctAttrs).draw(in: textRect)
    }

    private static func usageNSColor(percent: Int) -> NSColor {
        switch percent {
        case ..<65: return NSColor(calibratedRed: 0.20, green: 0.80, blue: 0.45, alpha: 1.0)
        case 65..<90: return NSColor(calibratedRed: 0.98, green: 0.64, blue: 0.14, alpha: 1.0)
        default: return NSColor(calibratedRed: 0.96, green: 0.30, blue: 0.35, alpha: 1.0)
        }
    }
}
