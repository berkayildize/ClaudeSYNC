import ClaudeSYNCCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppViewModel
    var useNativeGlassBackdrop: Bool = true

    private var l10n: L10n { viewModel.l10n }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            Group {
                switch viewModel.activeTab {
                case .sessions:
                    SessionsWorkspaceView(viewModel: viewModel, isWideLayout: false)
                case .limits:
                    LimitsDashboardView(viewModel: viewModel, isWideLayout: false)
                case .settings:
                    SettingsView(viewModel: viewModel, isWideLayout: false)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .layoutPriority(1)

            footerBar
        }
        .frame(width: BridgeTheme.popoverWidth, height: BridgeTheme.popoverHeight)
        .background {
            if useNativeGlassBackdrop {
                MacOSGlassBackdrop(material: .popover, blendingMode: .behindWindow)
            }
        }
        .onAppear {
            viewModel.refresh(userInitiated: false)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                ClaudeSyncHeaderIcon(size: 26)

                VStack(alignment: .leading, spacing: 0.5) {
                    Text("ClaudeSYNC")
                        .font(.system(size: 12.5, weight: .semibold))
                        .lineLimit(1)
                    Text(
                        viewModel.isCrossProfileMode
                            ? l10n.t("Çift Profil", "Dual Profile")
                            : l10n.t("Tek Profil", "Single Profile")
                    )
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
            .fixedSize()

            Spacer(minLength: 4)

            LiquidGlassSegmentedControl(
                items: PopoverTab.allCases,
                selection: $viewModel.activeTab,
                title: { $0.title(l10n) },
                icon: { $0.icon },
                compact: true
            )
            .frame(width: 244)

            Button {
                viewModel.openMainWindow()
            } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(width: 27, height: 27)
                    .liquidGlassCapsule(tint: nil, interactive: false)
            }
            .buttonStyle(TactileScaleButtonStyle())
            .help(l10n.t("Ana ClaudeSYNC penceresini aç (⌘O)", "Open main ClaudeSYNC window (⌘O)"))

            Button {
                viewModel.refresh(userInitiated: true)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.82))
                    .frame(width: 27, height: 27)
                    .rotationEffect(.degrees(viewModel.isRefreshing ? 360 : 0))
                    .animation(
                        viewModel.isRefreshing ? .easeInOut(duration: 0.45) : .default,
                        value: viewModel.isRefreshing
                    )
                    .liquidGlassCapsule(tint: nil, interactive: false)
            }
            .buttonStyle(TactileScaleButtonStyle())
            .help(l10n.t("Oturumları ve limitleri yenile", "Refresh sessions and limits"))
        }
        .padding(.horizontal, BridgeTheme.hPad)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                Circle()
                    .fill(viewModel.liveSessionCount > 0 ? Color(nsColor: .systemGreen) : .secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(
                    viewModel.liveSessionCount > 0
                        ? l10n.t(
                            "\(viewModel.liveSessionCount) canlı · \(viewModel.filteredSourceSessions.count) listelenen",
                            "\(viewModel.liveSessionCount) live · \(viewModel.filteredSourceSessions.count) shown"
                        )
                        : l10n.t(
                            "\(viewModel.filteredSourceSessions.count) oturum",
                            "\(viewModel.filteredSourceSessions.count) sessions"
                        )
                )
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            if viewModel.settings.autoSyncSharedCards {
                Text(l10n.t("· Oto Kart", "· Auto Sync"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button(l10n.t("Uygulamayı Aç", "Open App")) {
                viewModel.openMainWindow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(BridgeTheme.primaryAccent)

            Text("·")
                .foregroundStyle(.quaternary)

            Button(l10n.t("Yedekler", "Backups")) {
                viewModel.openBackupsFolder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.quaternary)

            Button(l10n.t("Çıkış", "Quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, BridgeTheme.hPad)
        .padding(.vertical, 9)
    }
}
