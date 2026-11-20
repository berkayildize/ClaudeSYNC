import ClaudeSYNCCore
import SwiftUI

struct MenuBarContentView: View {
    @ObservedObject var viewModel: AppViewModel
    var useNativeGlassBackdrop: Bool = true

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
                    Text(viewModel.isCrossProfileMode ? "Çift Profil" : "Tek Profil")
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
                title: { $0.rawValue },
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
            .help("Ana ClaudeSYNC penceresini aç (⌘O)")

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
            .help("Oturumları ve limitleri yenile")
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
                        ? "\(viewModel.liveSessionCount) canlı · \(viewModel.filteredSourceSessions.count) listelenen"
                        : "\(viewModel.filteredSourceSessions.count) oturum"
                )
                .font(.system(size: 10.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }

            if viewModel.settings.autoSyncSharedCards {
                Text("· Oto Kart")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            Button("Uygulamayı Aç") {
                viewModel.openMainWindow()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(BridgeTheme.primaryAccent)

            Text("·")
                .foregroundStyle(.quaternary)

            Button("Yedekler") {
                viewModel.openBackupsFolder()
            }
            .buttonStyle(.plain)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.secondary)

            Text("·")
                .foregroundStyle(.quaternary)

            Button("Çıkış") {
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
