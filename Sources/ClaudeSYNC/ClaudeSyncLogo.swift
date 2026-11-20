import AppKit
import SwiftUI

enum ClaudeSyncVectorArt {
    /// Signature Anthropic/Claude flat terracotta accent — solid color, zero gradients.
    static let claudeTerracottaNS = NSColor(calibratedRed: 0.85, green: 0.47, blue: 0.34, alpha: 1.0)
    static let claudeTerracotta = Color(red: 0.85, green: 0.47, blue: 0.34)

    /// Draws a crisp geometric 10-ray Claude-style starburst centered at `center`.
    static func drawStarburst(
        in cg: CGContext,
        center: CGPoint,
        outerRadius: CGFloat,
        color: CGColor
    ) {
        cg.saveGState()
        cg.setFillColor(color)

        let rayCount = 10
        let innerHub = outerRadius * 0.24

        // Central hub circle
        cg.fillEllipse(in: CGRect(
            x: center.x - innerHub,
            y: center.y - innerHub,
            width: innerHub * 2,
            height: innerHub * 2
        ))

        for i in 0..<rayCount {
            let angle = (CGFloat(i) / CGFloat(rayCount)) * (.pi * 2.0) + (.pi / 20.0)
            let isPrimaryRay = (i % 2 == 0)
            let length = outerRadius * (isPrimaryRay ? 1.0 : 0.82)
            let halfBaseWidth = outerRadius * (isPrimaryRay ? 0.105 : 0.088)
            let halfTipWidth = outerRadius * (isPrimaryRay ? 0.068 : 0.055)

            cg.saveGState()
            cg.translateBy(x: center.x, y: center.y)
            cg.rotate(by: angle)

            let rayPath = CGMutablePath()
            rayPath.move(to: CGPoint(x: innerHub * 0.55, y: -halfBaseWidth))
            rayPath.addLine(to: CGPoint(x: length - halfTipWidth, y: -halfTipWidth))
            rayPath.addArc(
                center: CGPoint(x: length - halfTipWidth, y: 0),
                radius: halfTipWidth,
                startAngle: -.pi / 2,
                endAngle: .pi / 2,
                clockwise: false
            )
            rayPath.addLine(to: CGPoint(x: innerHub * 0.55, y: halfBaseWidth))
            rayPath.closeSubpath()

            cg.addPath(rayPath)
            cg.fillPath()
            cg.restoreGState()
        }
        cg.restoreGState()
    }

    /// Draws twin opposing transfer arrows (`⇄`) centered inside `center` with half-span `radius`.
    static func drawTransferArrows(
        in cg: CGContext,
        center: CGPoint,
        radius: CGFloat,
        color: CGColor,
        lineWidth: CGFloat
    ) {
        cg.saveGState()
        cg.setStrokeColor(color)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        let dx = radius * 0.62
        let dy = radius * 0.30
        let head = radius * 0.28

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

    /// Draws the complete ClaudeSYNC menu-bar emblem (Claude starburst + compact transfer badge).
    static func drawMenuBarEmblem(
        in cg: CGContext,
        rect: CGRect,
        starburstColor: CGColor,
        badgeBgColor: CGColor,
        arrowColor: CGColor,
        cutoutColor: CGColor?
    ) {
        // Starburst slightly shifted top-left to balance the corner sync badge
        let starCenter = CGPoint(x: rect.midX - rect.width * 0.08, y: rect.midY + rect.height * 0.06)
        let starRadius = min(rect.width, rect.height) * 0.43
        drawStarburst(in: cg, center: starCenter, outerRadius: starRadius, color: starburstColor)

        // Bottom-right circular transfer badge
        let badgeRadius = min(rect.width, rect.height) * 0.255
        let badgeCenter = CGPoint(x: rect.maxX - badgeRadius - 0.5, y: rect.minY + badgeRadius + 0.5)

        if let cutoutColor {
            let ringR = badgeRadius + 1.1
            cg.setFillColor(cutoutColor)
            cg.fillEllipse(in: CGRect(
                x: badgeCenter.x - ringR,
                y: badgeCenter.y - ringR,
                width: ringR * 2,
                height: ringR * 2
            ))
        }

        cg.setFillColor(badgeBgColor)
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
            color: arrowColor,
            lineWidth: max(1.0, badgeRadius * 0.25)
        )
    }
}

/// Crisp SwiftUI badge used in the popover header (zero gradients, Retina-rendered vector).
struct ClaudeSyncHeaderIcon: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 28

    var body: some View {
        let isDark = (scheme == .dark)
        Canvas { context, canvasSize in
            let rect = CGRect(origin: .zero, size: canvasSize)
            let corner = canvasSize.width * 0.26
            let tilePath = Path(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: corner)

            // Clean flat obsidian tile (Dark) or soft graphite tile (Light)
            let tileFill = isDark
                ? Color(red: 0.14, green: 0.15, blue: 0.18)
                : Color(red: 0.15, green: 0.16, blue: 0.19)
            context.fill(tilePath, with: .color(tileFill))
            context.stroke(
                tilePath,
                with: .color(Color.white.opacity(isDark ? 0.16 : 0.10)),
                lineWidth: 0.75
            )

            context.withCGContext { cg in
                // Flip vertically so CoreGraphics math matches AppKit coordinates cleanly
                cg.translateBy(x: 0, y: canvasSize.height)
                cg.scaleBy(x: 1, y: -1)

                let inner = rect.insetBy(dx: canvasSize.width * 0.14, dy: canvasSize.height * 0.14)
                ClaudeSyncVectorArt.drawMenuBarEmblem(
                    in: cg,
                    rect: inner,
                    starburstColor: ClaudeSyncVectorArt.claudeTerracottaNS.cgColor,
                    badgeBgColor: NSColor.white.cgColor,
                    arrowColor: NSColor(calibratedRed: 0.13, green: 0.14, blue: 0.17, alpha: 1.0).cgColor,
                    cutoutColor: NSColor(calibratedRed: 0.14, green: 0.15, blue: 0.18, alpha: 1.0).cgColor
                )
            }
        }
        .frame(width: size, height: size)
    }
}
