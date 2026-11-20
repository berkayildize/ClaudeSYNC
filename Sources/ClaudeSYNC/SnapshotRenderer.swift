import AppKit
import ClaudeSYNCCore
import SwiftUI

@MainActor
enum SnapshotRenderer {
    static func runIfRequested(viewModel: AppViewModel) -> Bool {
        let args = CommandLine.arguments
        let isDemo = args.contains("--demo-snapshot")
        let flag = isDemo ? "--demo-snapshot" : "--snapshot"
        guard let idx = args.firstIndex(of: flag), idx + 1 < args.count else {
            return false
        }
        let outputDir = URL(fileURLWithPath: args[idx + 1], isDirectory: true)
        let isTurkish: Bool = {
            if args.contains("--lang=tr") { return true }
            if args.contains("--lang=en") { return false }
            return false
        }()

        Task { @MainActor in
            if isDemo {
                viewModel.loadSyntheticDemoData(isTurkish: isTurkish)
            } else {
                for _ in 0..<30 {
                    if !viewModel.isRefreshing && viewModel.lastRefreshedAt != nil { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            await captureAll(viewModel: viewModel, outputDir: outputDir, isTurkish: isTurkish)
            fflush(stdout)
            exit(0)
        }
        return true
    }

    private static func captureAll(viewModel: AppViewModel, outputDir: URL, isTurkish: Bool) async {
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // 1. Full Standalone Desktop App Windows (920 × 650)
        viewModel.isShowingOnboarding = false
        let mainSpecs: [(MainAppSection, NSAppearance.Name, String)] = [
            (.sessions, .darkAqua, "app-main-dark.png"),
            (.limits, .darkAqua, "app-limits-dark.png"),
            (.profiles, .darkAqua, "app-profiles-dark.png"),
            (.settings, .darkAqua, "app-settings-dark.png"),
            (.sessions, .aqua, "app-main-light.png")
        ]

        for (section, appearanceName, filename) in mainSpecs {
            viewModel.mainSection = section
            let isDark = (appearanceName == .darkAqua)
            await renderWindow(
                content: MainWindowView(viewModel: viewModel, useNativeGlassBackdrop: false, includeTrafficLightInset: true),
                width: 920,
                height: 650,
                appearanceName: appearanceName,
                isDark: isDark,
                showTrafficLights: true,
                to: outputDir.appendingPathComponent(filename)
            )
            print("Saved \(filename)")
        }

        // 2. Onboarding Setup Wizard Screenshots (Welcome & Permissions steps)
        viewModel.isShowingOnboarding = true
        for (step, filename) in [(OnboardingStep.welcome, "app-onboarding-welcome-dark.png"), (OnboardingStep.permissions, "app-onboarding-permissions-dark.png")] {
            viewModel.onboardingStep = step
            await renderWindow(
                content: MainWindowView(viewModel: viewModel, useNativeGlassBackdrop: false, includeTrafficLightInset: true),
                width: 920,
                height: 650,
                appearanceName: .darkAqua,
                isDark: true,
                showTrafficLights: true,
                to: outputDir.appendingPathComponent(filename)
            )
            print("Saved \(filename)")
        }
        viewModel.isShowingOnboarding = false

        // 3. Compact Menu Bar Popover (512 × 688)
        viewModel.activeTab = .sessions
        await renderWindow(
            content: MenuBarContentView(viewModel: viewModel, useNativeGlassBackdrop: false),
            width: BridgeTheme.popoverWidth,
            height: BridgeTheme.popoverHeight,
            appearanceName: .darkAqua,
            isDark: true,
            showTrafficLights: false,
            to: outputDir.appendingPathComponent("menubar-popover-dark.png")
        )
        print("Saved menubar-popover-dark.png")

        // 4. Menu Bar Limit Bars & Icon Showcase
        await renderMenuBarShowcase(
            viewModel: viewModel,
            isTurkish: isTurkish,
            to: outputDir.appendingPathComponent("menubar-bars.png")
        )
        print("Saved menubar-bars.png")
    }

    private static func renderWindow<Content: View>(
        content: Content,
        width: CGFloat,
        height: CGFloat,
        appearanceName: NSAppearance.Name,
        isDark: Bool,
        showTrafficLights: Bool,
        to fileURL: URL
    ) async {
        guard let appearance = NSAppearance(named: appearanceName) else { return }
        NSApp.appearance = appearance

        let pad: CGFloat = 28
        let canvasW = width + pad * 2
        let canvasH = height + pad * 2

        let previewRoot = ZStack {
            Color(
                red: isDark ? 0.08 : 0.87,
                green: isDark ? 0.09 : 0.89,
                blue: isDark ? 0.12 : 0.92
            )

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isDark
                            ? Color(red: 0.11, green: 0.12, blue: 0.15)
                            : Color(red: 0.96, green: 0.97, blue: 0.98)
                    )

                content
                    .frame(width: width, height: height)

                if showTrafficLights {
                    HStack(spacing: 7) {
                        Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.34)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.18)).frame(width: 11, height: 11)
                        Circle().fill(Color(red: 0.15, green: 0.79, blue: 0.25)).frame(width: 11, height: 11)
                    }
                    .padding(.leading, 14)
                    .padding(.top, 12)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isDark ? Color.white.opacity(0.16) : Color.black.opacity(0.10),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(isDark ? 0.45 : 0.14), radius: 18, y: 8)
        }
        .frame(width: canvasW, height: canvasH)
        .environment(\.colorScheme, isDark ? .dark : .light)

        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: canvasW, height: canvasH),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.isOpaque = false
        window.backgroundColor = .clear

        let host = NSHostingView(rootView: previewRoot)
        host.frame = NSRect(x: 0, y: 0, width: canvasW, height: canvasH)
        host.appearance = appearance
        window.contentView = host
        window.orderBack(nil)

        try? await Task.sleep(nanoseconds: 350_000_000)

        appearance.performAsCurrentDrawingAppearance {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                }
            }
        }

        window.orderOut(nil)
        window.close()
    }

    private static func renderMenuBarShowcase(viewModel: AppViewModel, isTurkish: Bool, to fileURL: URL) async {
        let darkDual = MenuBarWidgetRenderer.shared.image(
            mode: .iconAndBothAccounts,
            accounts: viewModel.accounts,
            activeAccount: viewModel.activeAccount,
            isSwitching: false,
            isTurkish: isTurkish,
            overrideDark: true
        )
        let darkActive = MenuBarWidgetRenderer.shared.image(
            mode: .iconAndActiveUsage,
            accounts: viewModel.accounts,
            activeAccount: viewModel.activeAccount,
            isSwitching: false,
            isTurkish: isTurkish,
            overrideDark: true
        )
        let lightDual = MenuBarWidgetRenderer.shared.image(
            mode: .iconAndBothAccounts,
            accounts: viewModel.accounts,
            activeAccount: viewModel.activeAccount,
            isSwitching: false,
            isTurkish: isTurkish,
            overrideDark: false
        )
        let clockStr = isTurkish ? "Cum 12:48" : "Fri 12:48"

        let showcase = VStack(spacing: 18) {
            HStack(spacing: 16) {
                ClaudeSyncHeaderIcon(size: 68)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ClaudeSYNC")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                    Text(isTurkish ? "macOS Üst Bar Limit Barları & İkon" : "macOS Menu Bar Limit Bars & Icon")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isTurkish ? "KOYU ÜST BAR · İKİ HESAP BAR (2x)" : "DARK MENU BAR · DUAL ACCOUNT BARS (2x)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 14) {
                    Spacer()
                    Image(nsImage: darkDual)
                        .interpolation(.high)
                        .scaleEffect(2.0)
                        .frame(width: darkDual.size.width * 2, height: darkDual.size.height * 2)
                    Text(clockStr)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.16, green: 0.17, blue: 0.20)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isTurkish ? "KOYU ÜST BAR · AKTİF 5s / 7g BAR (2x)" : "DARK MENU BAR · ACTIVE 5h / 7d BARS (2x)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 14) {
                    Spacer()
                    Image(nsImage: darkActive)
                        .interpolation(.high)
                        .scaleEffect(2.0)
                        .frame(width: darkActive.size.width * 2, height: darkActive.size.height * 2)
                    Text(clockStr)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.16, green: 0.17, blue: 0.20)))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(isTurkish ? "AÇIK ÜST BAR · İKİ HESAP BAR (2x)" : "LIGHT MENU BAR · DUAL ACCOUNT BARS (2x)")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                HStack(spacing: 14) {
                    Spacer()
                    Image(nsImage: lightDual)
                        .interpolation(.high)
                        .scaleEffect(2.0)
                        .frame(width: lightDual.size.width * 2, height: lightDual.size.height * 2)
                    Text(clockStr)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.black.opacity(0.85))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.92, green: 0.93, blue: 0.95)))
            }
        }
        .padding(24)
        .frame(width: 480, height: 420)
        .background(Color(red: 0.09, green: 0.10, blue: 0.12))
        .environment(\.colorScheme, .dark)

        guard let appearance = NSAppearance(named: .darkAqua) else { return }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: 480, height: 420),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        let host = NSHostingView(rootView: showcase)
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 420)
        host.appearance = appearance
        window.contentView = host
        window.orderBack(nil)
        try? await Task.sleep(nanoseconds: 250_000_000)

        appearance.performAsCurrentDrawingAppearance {
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                host.cacheDisplay(in: host.bounds, to: rep)
                if let pngData = rep.representation(using: .png, properties: [:]) {
                    try? pngData.write(to: fileURL)
                }
            }
        }
        window.orderOut(nil)
        window.close()
    }
}
