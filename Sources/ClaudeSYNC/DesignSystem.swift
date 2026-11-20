import AppKit
import ClaudeSYNCCore
import SwiftUI

enum BridgeTheme {
    static let popoverWidth: CGFloat = 512
    static let popoverHeight: CGFloat = 688
    static let hPad: CGFloat = 14
    static let cardRadius: CGFloat = 13
    static let innerRadius: CGFloat = 9

    /// Flat, crisp Apple macOS semantic colors — zero decorative gradients.
    static func usageColor(percent: Int) -> Color {
        switch percent {
        case ..<65: return Color(nsColor: .systemGreen)
        case 65..<90: return Color(nsColor: .systemOrange)
        default: return Color(nsColor: .systemRed)
        }
    }

    static var primaryAccent: Color {
        Color.accentColor
    }
}

// MARK: - Native macOS NSVisualEffectView Glass Shell

struct MacOSGlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        if nsView.material != material { nsView.material = material }
        if nsView.blendingMode != blendingMode { nsView.blendingMode = blendingMode }
    }
}

// MARK: - Zero-Overhead Apple Hairline Glass Surface (120Hz ProMotion Locked)

struct LiquidGlassSurfaceModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    let cornerRadius: CGFloat
    let tint: Color?
    let strokeAccent: Color?
    let elevated: Bool

    func body(content: Content) -> some View {
        let isDark = (scheme == .dark)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        let fillColor: Color = {
            if let tint {
                return tint.opacity(isDark ? 0.11 : 0.08)
            }
            return isDark
                ? Color.white.opacity(elevated ? 0.08 : 0.055)
                : Color.white.opacity(elevated ? 0.78 : 0.62)
        }()

        let borderColor: Color = strokeAccent ?? (
            isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08)
        )

        return content
            .background(shape.fill(fillColor))
            .overlay(shape.strokeBorder(borderColor, lineWidth: 0.75))
    }
}

struct LiquidGlassCapsuleModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    let tint: Color?
    let elevated: Bool

    func body(content: Content) -> some View {
        let isDark = (scheme == .dark)

        let fillColor: Color = {
            if let tint {
                return tint.opacity(isDark ? 0.16 : 0.12)
            }
            return isDark
                ? Color.white.opacity(elevated ? 0.11 : 0.07)
                : Color.white.opacity(elevated ? 0.88 : 0.68)
        }()

        let borderColor: Color = isDark
            ? Color.white.opacity(elevated ? 0.16 : 0.11)
            : Color.black.opacity(0.09)

        return content
            .background(Capsule().fill(fillColor))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: 0.75))
    }
}

extension View {
    func liquidGlassCard(
        cornerRadius: CGFloat = BridgeTheme.cardRadius,
        tint: Color? = nil,
        interactive: Bool = false,
        strokeAccent: Color? = nil,
        elevated: Bool = false
    ) -> some View {
        modifier(
            LiquidGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint,
                strokeAccent: strokeAccent,
                elevated: elevated || interactive
            )
        )
    }

    func liquidGlassCapsule(
        tint: Color? = nil,
        interactive: Bool = true,
        elevated: Bool = false
    ) -> some View {
        modifier(LiquidGlassCapsuleModifier(tint: tint, elevated: elevated || interactive))
    }

    @ViewBuilder
    func nativeGlassButton(prominent: Bool = false) -> some View {
        if prominent {
            self.buttonStyle(.borderedProminent)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}

// MARK: - Crisp Static Apple Status Dot (Zero Idle GPU Cost)

struct PulseStatusDot: View {
    let color: Color
    var size: CGFloat = 6.5
    var isPulsing: Bool = false

    var body: some View {
        ZStack {
            if isPulsing {
                Circle()
                    .fill(color.opacity(0.24))
                    .frame(width: size * 1.85, height: size * 1.85)
            }
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .frame(width: size * 1.85, height: size * 1.85)
    }
}

// MARK: - Snappy Flat Circular Gauge (Zero Gradients, Zero Shadow Cost)

struct AnimatedCircularGauge: View {
    @Environment(\.colorScheme) private var scheme

    let percent: Int?
    let title: String
    var diameter: CGFloat = 46
    var lineWidth: CGFloat = 4.25

    private var targetFraction: Double {
        guard let p = percent else { return 0 }
        return min(max(Double(p) / 100.0, 0), 1)
    }

    private var displayColor: Color {
        guard let p = percent else { return .secondary }
        return BridgeTheme.usageColor(percent: p)
    }

    var body: some View {
        let isDark = (scheme == .dark)
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08), lineWidth: lineWidth)

                if let p = percent {
                    Circle()
                        .trim(from: 0, to: max(targetFraction, p > 0 ? 0.035 : 0))
                        .stroke(
                            displayColor,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .animation(.easeOut(duration: 0.22), value: targetFraction)
                }

                Text(percent.map { "\($0)%" } ?? "—")
                    .font(.system(size: diameter * 0.255, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percent != nil ? .primary : .tertiary)
            }
            .frame(width: diameter, height: diameter)

            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

// MARK: - Flat Crisp Horizontal Usage Meter

struct LinearUsageBar: View {
    @Environment(\.colorScheme) private var scheme

    let label: String
    let percent: Int?
    var subtitle: String? = nil

    private var fraction: Double {
        guard let p = percent else { return 0 }
        return min(max(Double(p) / 100.0, 0), 1)
    }

    var body: some View {
        let isDark = (scheme == .dark)
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if let sub = subtitle {
                    Text(sub)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Text(percent.map { "%\($0)" } ?? "—")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(percent.map { BridgeTheme.usageColor(percent: $0) } ?? .secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.08))

                    if let p = percent {
                        Capsule()
                            .fill(BridgeTheme.usageColor(percent: p))
                            .frame(width: max(p > 0 ? 5 : 0, geo.size.width * fraction))
                            .animation(.easeOut(duration: 0.2), value: fraction)
                    }
                }
            }
            .frame(height: 6)
        }
    }
}

// MARK: - Clean Flat Hairline Sparkline (Activity Monitor Aesthetic)

struct UsageSparkline: View {
    let points: [UsageSamplePoint]
    let metric: Metric

    enum Metric {
        case sevenDay
        case fiveHour
    }

    private var values: [Double] {
        points.compactMap { point in
            switch metric {
            case .sevenDay: return point.sevenDay.map(Double.init)
            case .fiveHour: return point.fiveHour.map(Double.init)
            }
        }
    }

    var body: some View {
        let vals = values
        let latest = Int(vals.last ?? 0)
        let strokeColor = BridgeTheme.usageColor(percent: latest)

        GeometryReader { _ in
            if vals.count >= 2 {
                Canvas { context, size in
                    let padY: CGFloat = 6
                    let padX: CGFloat = 5
                    let w = size.width - padX * 2
                    let h = size.height - padY * 2
                    let stepX = w / CGFloat(max(vals.count - 1, 1))

                    let coords: [CGPoint] = vals.enumerated().map { idx, val in
                        let x = padX + CGFloat(idx) * stepX
                        let norm = min(max(val / 100.0, 0), 1)
                        let y = padY + h * (1.0 - CGFloat(norm))
                        return CGPoint(x: x, y: y)
                    }

                    var linePath = Path()
                    linePath.move(to: coords[0])
                    for i in 1..<coords.count {
                        let prev = coords[i - 1]
                        let curr = coords[i]
                        let mid = CGPoint(x: (prev.x + curr.x) / 2, y: (prev.y + curr.y) / 2)
                        linePath.addQuadCurve(to: mid, control: prev)
                    }
                    if let last = coords.last {
                        linePath.addLine(to: last)
                    }

                    var areaPath = linePath
                    if let last = coords.last, let first = coords.first {
                        areaPath.addLine(to: CGPoint(x: last.x, y: size.height))
                        areaPath.addLine(to: CGPoint(x: first.x, y: size.height))
                        areaPath.closeSubpath()
                    }

                    context.fill(areaPath, with: .color(strokeColor.opacity(0.09)))
                    context.stroke(
                        linePath,
                        with: .color(strokeColor),
                        style: StrokeStyle(lineWidth: 1.75, lineCap: .round, lineJoin: .round)
                    )

                    if let last = coords.last {
                        let dotRect = CGRect(x: last.x - 2.75, y: last.y - 2.75, width: 5.5, height: 5.5)
                        context.fill(Path(ellipseIn: dotRect), with: .color(strokeColor))
                    }
                }
            } else {
                HStack {
                    Spacer()
                    Text("Grafik için yeterli örnek birikmedi")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Snappy 120Hz Sliding Segmented Control

struct LiquidGlassSegmentedControl<Item: Hashable & Identifiable>: View {
    @Environment(\.colorScheme) private var scheme

    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var icon: ((Item) -> String)? = nil
    var compact: Bool = false

    @Namespace private var ns

    var body: some View {
        let isDark = (scheme == .dark)

        HStack(spacing: 2) {
            ForEach(items) { item in
                let isSelected = (selection == item)
                Button {
                    withAnimation(.snappy(duration: 0.16, extraBounce: 0.0)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 4) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
                        }
                        Text(title(item))
                            .font(.system(size: compact ? 10.5 : 11, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, compact ? 4.5 : 5.5)
                    .padding(.horizontal, compact ? 6 : 8)
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(isDark ? Color.white.opacity(0.16) : Color.white.opacity(0.94))
                                .overlay(
                                    Capsule()
                                        .strokeBorder(
                                            isDark ? Color.white.opacity(0.18) : Color.black.opacity(0.08),
                                            lineWidth: 0.5
                                        )
                                )
                                .matchedGeometryEffect(id: "seg-pill", in: ns)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(isDark ? Color.black.opacity(0.24) : Color.black.opacity(0.06))
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
        }
    }
}

// MARK: - Instant 120Hz Press Feedback (Zero Bounce Lag)

struct TactileScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.78 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
