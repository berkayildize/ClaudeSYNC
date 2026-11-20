import ClaudeSYNCCore
import SwiftUI

struct MainWindowView: View {
    @ObservedObject var viewModel: AppViewModel
    var useNativeGlassBackdrop: Bool = true
    var includeTrafficLightInset: Bool = false
    @Environment(\.colorScheme) private var scheme

    private var l10n: L10n { viewModel.l10n }

    var body: some View {
        Group {
            if viewModel.shouldShowOnboarding {
                OnboardingView(
                    viewModel: viewModel,
                    useNativeGlassBackdrop: useNativeGlassBackdrop,
                    includeTrafficLightInset: includeTrafficLightInset
                )
            } else {
                HStack(spacing: 0) {
                    sidebarColumn
                        .frame(width: 216)

                    Rectangle()
                        .fill(scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                        .frame(width: 0.75)

                    detailColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 800, idealWidth: 920, minHeight: 580, idealHeight: 650)
                .background {
                    if useNativeGlassBackdrop {
                        MacOSGlassBackdrop(material: .underWindowBackground, blendingMode: .behindWindow)
                    }
                }
            }
        }
        .onAppear {
            viewModel.refresh(userInitiated: false)
        }
    }

    // MARK: - Left Native macOS Sidebar

    private var sidebarColumn: some View {
        let isDark = (scheme == .dark)
        return VStack(spacing: 0) {
            // Brand Header
            HStack(spacing: 10) {
                ClaudeSyncHeaderIcon(size: 32)
                VStack(alignment: .leading, spacing: 1) {
                    Text("ClaudeSYNC")
                        .font(.system(size: 14, weight: .bold))
                    Text(
                        viewModel.isCrossProfileMode
                            ? l10n.t("Çift Profil Aktif", "Dual Profile Active")
                            : l10n.t("Tek Profil Modu", "Single Profile Mode")
                    )
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, includeTrafficLightInset ? 36 : 16)
            .padding(.bottom, 14)

            // Navigation Items
            VStack(spacing: 3) {
                ForEach(MainAppSection.allCases) { section in
                    sidebarItem(section)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            // Mini Live Telemetry Summary inside Sidebar
            if !viewModel.accounts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(l10n.t("HIZLI LİMİT DURUMU", "LIVE LIMIT STATUS"))
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.7)

                    ForEach(viewModel.accounts.prefix(2)) { acc in
                        sidebarAccountMeter(acc)
                    }
                }
                .padding(10)
                .liquidGlassCard(cornerRadius: 10)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }

            // Quick Menu Bar Toggle right in Sidebar Footer
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(l10n.t("Üst Bar Simgesi", "Menu Bar Icon"))
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Toggle(
                        "",
                        isOn: Binding(
                            get: { viewModel.showMenuBarExtra },
                            set: { viewModel.setShowMenuBarExtra($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8.5)

                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.06) : Color.black.opacity(0.06))
                    .frame(height: 0.5)

                // Subtle Creator Attribution & Social Links
                HStack(spacing: 6) {
                    Text(l10n.t("by \(CreatorLinks.handle)", "by \(CreatorLinks.handle)"))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)

                    Spacer()

                    Button {
                        NSWorkspace.shared.open(CreatorLinks.githubURL)
                    } label: {
                        GitHubBrandMark(size: 11.5)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                    .help("GitHub — https://github.com/berkayildize/")

                    Button {
                        NSWorkspace.shared.open(CreatorLinks.xURL)
                    } label: {
                        XBrandMark(size: 9.5)
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
                    }
                    .buttonStyle(TactileScaleButtonStyle())
                    .help("X (Twitter) — https://x.com/berkayildize/")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6.5)
            }
            .background(isDark ? Color.white.opacity(0.035) : Color.black.opacity(0.03))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                    .frame(height: 0.5)
            }
        }
        .background {
            if useNativeGlassBackdrop {
                MacOSGlassBackdrop(material: .sidebar, blendingMode: .behindWindow)
            } else {
                isDark ? Color.white.opacity(0.03) : Color.black.opacity(0.025)
            }
        }
    }

    private func sidebarItem(_ section: MainAppSection) -> some View {
        let isSelected = (viewModel.mainSection == section)
        let isDark = (scheme == .dark)

        return Button {
            viewModel.mainSection = section
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.icon)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? BridgeTheme.primaryAccent : .secondary)
                    .frame(width: 18)

                Text(section.title(l10n))
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Spacer()

                if let badge = sidebarBadge(for: section) {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(isSelected ? 0.12 : 0.07)))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? (isDark ? Color.white.opacity(0.11) : Color.black.opacity(0.07))
                            : Color.clear
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarBadge(for section: MainAppSection) -> String? {
        switch section {
        case .sessions:
            if viewModel.liveSessionCount > 0 {
                return l10n.t("\(viewModel.liveSessionCount) canlı", "\(viewModel.liveSessionCount) live")
            }
            let count = viewModel.sourceAccount?.activeSessions.count ?? 0
            return count > 0 ? "\(count)" : nil
        case .limits:
            if let pct = viewModel.activeAccount?.usage?.peakPercent { return "\(pct)%" }
            return nil
        case .profiles:
            return "\(viewModel.settings.allProfiles.count)"
        case .settings:
            return nil
        }
    }

    private func sidebarAccountMeter(_ acc: AccountSlot) -> some View {
        let peak = acc.usage?.peakPercent
        return VStack(spacing: 3.5) {
            HStack(spacing: 5) {
                Circle()
                    .fill(
                        acc.usage?.isExhausted == true
                            ? Color(nsColor: .systemRed)
                            : (acc.isActiveAccount ? Color(nsColor: .systemGreen) : .secondary.opacity(0.45))
                    )
                    .frame(width: 5.5, height: 5.5)
                Text(acc.displayName)
                    .font(.system(size: 10.5, weight: acc.isActiveAccount ? .semibold : .medium))
                    .lineLimit(1)
                Spacer()
                Text(peak.map { "\($0)%" } ?? "—")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(peak.map { BridgeTheme.usageColor(percent: $0) } ?? .secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    if let p = peak, p > 0 {
                        Capsule()
                            .fill(BridgeTheme.usageColor(percent: p))
                            .frame(width: max(4, geo.size.width * min(Double(p) / 100.0, 1.0)))
                    }
                }
            }
            .frame(height: 4)
        }
    }

    // MARK: - Right Detail Workspace

    private var detailColumn: some View {
        let isDark = (scheme == .dark)
        return VStack(spacing: 0) {
            // Top Detail Toolbar
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(sectionTitle)
                        .font(.system(size: 15, weight: .semibold))
                    Text(sectionSubtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if viewModel.settings.autoSyncSharedCards {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color(nsColor: .systemGreen))
                            .frame(width: 5.5, height: 5.5)
                        Text(l10n.t("Oto Kart Açık", "Auto Sync On"))
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .liquidGlassCapsule(tint: nil, interactive: false)
                }

                Button {
                    viewModel.openBackupsFolder()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 10.5))
                        Text(l10n.t("Yedekler", "Backups"))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .padding(.horizontal, 9)
                    .frame(height: 27)
                    .liquidGlassCapsule(tint: nil, interactive: false)
                }
                .buttonStyle(TactileScaleButtonStyle())

                Button {
                    viewModel.refresh(userInitiated: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))
                        .frame(width: 27, height: 27)
                        .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                        .animation(
                            viewModel.isRefreshing ? .easeInOut(duration: 0.45) : .default,
                            value: viewModel.isRefreshing
                        )
                        .liquidGlassCapsule(tint: nil, interactive: false)
                }
                .buttonStyle(TactileScaleButtonStyle())
                .help(l10n.t("Yenile (⌘R)", "Refresh (⌘R)"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isDark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                    .frame(height: 0.5)
            }

            // Detail Workspace Content
            Group {
                switch viewModel.mainSection {
                case .sessions:
                    SessionsWorkspaceView(viewModel: viewModel, isWideLayout: true)
                case .limits:
                    LimitsDashboardView(viewModel: viewModel, isWideLayout: true)
                case .profiles:
                    ProfilesManagerView(viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: viewModel, isWideLayout: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var sectionTitle: String {
        switch viewModel.mainSection {
        case .sessions: return l10n.t("Oturumlar", "Sessions")
        case .limits: return l10n.t("Limitler & Otomatik Geçiş", "Limits & Auto-Failover")
        case .profiles: return l10n.t("Claude Desktop Profilleri", "Claude Desktop Profiles")
        case .settings: return l10n.t("Ayarlar", "Settings")
        }
    }

    private var sectionSubtitle: String {
        switch viewModel.mainSection {
        case .sessions:
            return l10n.t(
                "Hesaplar arasında yerel oturum kartlarını aktarın, eşitleyin ve bağlam kaybetmeden devam edin",
                "Transfer and sync local session cards across accounts without losing active context"
            )
        case .limits:
            return l10n.t(
                "5 saatlik ve 7 günlük kullanım göstergeleri, yenilenme sayaçları ve otomatik geçiş kuralları",
                "Real-time 5-hour & 7-day usage gauges, reset countdowns, and automatic failover rules"
            )
        case .profiles:
            return l10n.t(
                "Çıkış/giriş yapmadan paralel çalışan izole Claude Desktop profilleri",
                "Isolated Claude Desktop profiles running side by side with zero logout"
            )
        case .settings:
            return l10n.t(
                "Dil, ilk kurulum sihirbazı, üst bar kontrolü, hesap isimleri ve sistem tercihleri",
                "Language, setup wizard, menu bar controls, account nicknames, and system preferences"
            )
        }
    }
}
