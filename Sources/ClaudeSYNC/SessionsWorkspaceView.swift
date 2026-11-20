import ClaudeSYNCCore
import SwiftUI

struct SessionsWorkspaceView: View {
    @ObservedObject var viewModel: AppViewModel
    var isWideLayout: Bool = false
    @State private var swapRotation: Double = 0

    private var hPad: CGFloat { isWideLayout ? 16 : BridgeTheme.hPad }

    var body: some View {
        VStack(spacing: isWideLayout ? 12 : 10) {
            if let banner = viewModel.statusBanner {
                statusBannerView(banner)
                    .padding(.horizontal, hPad)
            }

            if viewModel.accounts.isEmpty {
                emptyAccountsView
            } else {
                twinAccountCardsSection
                    .padding(.horizontal, hPad)

                unifiedActionRail
                    .padding(.horizontal, hPad)

                searchAndFilterRow
                    .padding(.horizontal, hPad)

                sessionListSection
            }
        }
        .padding(.top, isWideLayout ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Symmetric Twin Account Cards

    private var twinAccountCardsSection: some View {
        ZStack {
            HStack(spacing: 12) {
                symmetricAccountCard(
                    role: "KAYNAK",
                    account: viewModel.sourceAccount,
                    isSource: true
                )
                symmetricAccountCard(
                    role: "HEDEF",
                    account: viewModel.targetAccount,
                    isSource: false
                )
            }

            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    swapRotation += 180
                }
                viewModel.swapAccounts()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .rotationEffect(.degrees(swapRotation))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color(nsColor: .windowBackgroundColor)))
                    .liquidGlassCapsule(tint: nil, interactive: false, elevated: true)
            }
            .buttonStyle(TactileScaleButtonStyle())
            .disabled(viewModel.accounts.count < 2)
            .help("Kaynak ve hedef hesabı değiştir")
        }
    }

    private func symmetricAccountCard(role: String, account: AccountSlot?, isSource: Bool) -> some View {
        let isExhausted = account?.usage?.isExhausted == true
        let isActive = account?.isActiveAccount == true
        let strokeColor: Color? = isExhausted
            ? Color(nsColor: .systemRed).opacity(0.32)
            : (isActive ? Color(nsColor: .systemGreen).opacity(0.28) : nil)

        return VStack(spacing: 7) {
            HStack(spacing: 5) {
                Text(role)
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)

                Spacer(minLength: 2)

                if let acc = account {
                    HStack(spacing: 3) {
                        PulseStatusDot(
                            color: isExhausted
                                ? Color(nsColor: .systemRed)
                                : (acc.isActiveAccount ? Color(nsColor: .systemGreen) : Color(nsColor: .systemBlue)),
                            size: 5.5,
                            isPulsing: acc.isActiveAccount
                        )
                        Text(isExhausted ? "Limit Dolu" : (acc.isActiveAccount ? "Aktif" : "Hazır"))
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(
                                isExhausted
                                    ? Color(nsColor: .systemRed)
                                    : (acc.isActiveAccount ? Color(nsColor: .systemGreen) : .secondary)
                            )
                    }
                }
            }

            if let acc = account {
                if viewModel.accounts.count > 2 {
                    Menu {
                        ForEach(viewModel.accounts) { option in
                            Button {
                                if isSource {
                                    viewModel.selectSource(option.id)
                                } else {
                                    viewModel.selectTarget(option.id)
                                }
                            } label: {
                                Text("\(option.displayName) (\(option.activeSessions.count) aktif)")
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(acc.displayName)
                                .font(.system(size: 12.5, weight: .semibold))
                                .lineLimit(1)
                            Spacer(minLength: 2)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .menuStyle(.borderlessButton)
                } else {
                    HStack {
                        Text(acc.displayName)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(acc.profileName)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    AnimatedCircularGauge(
                        percent: acc.usage?.fiveHourPercent,
                        title: "5 Saat",
                        diameter: isWideLayout ? 48 : 42,
                        lineWidth: 4.25
                    )
                    Spacer(minLength: isWideLayout ? 24 : 16)
                    AnimatedCircularGauge(
                        percent: acc.usage?.sevenDayPercent,
                        title: "7 Gün",
                        diameter: isWideLayout ? 48 : 42,
                        lineWidth: 4.25
                    )
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Text("\(acc.activeSessions.count) aktif oturum")
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 2)

                    if let reset = acc.usage?.lastRateLimitHit?.resetsAt, reset > Date() {
                        Text(TurkishDateFormatter.countdownString(until: reset))
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Color(nsColor: .systemOrange))
                            .lineLimit(1)
                    } else if let ts = acc.usage?.updatedAt {
                        Text(TurkishDateFormatter.relativeString(from: ts))
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            } else {
                Spacer()
                Text("2. Hesap Bekleniyor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, minHeight: isWideLayout ? 132 : 124, maxHeight: isWideLayout ? 132 : 124)
        .liquidGlassCard(
            cornerRadius: BridgeTheme.cardRadius,
            tint: nil,
            interactive: false,
            strokeAccent: strokeColor
        )
    }

    // MARK: - Action Rail

    private var unifiedActionRail: some View {
        HStack(spacing: 8) {
            if viewModel.isCrossProfileMode {
                Button {
                    viewModel.instantSwitchToTarget()
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.isSwitchingNow {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 10.5, weight: .semibold))
                        }
                        Text("Çıkışsız Geçiş Yap")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
                    .background(Capsule().fill(BridgeTheme.primaryAccent))
                }
                .buttonStyle(TactileScaleButtonStyle())
                .disabled(viewModel.isBusy || viewModel.targetAccount == nil)
                .help("Canlı oturumları aktarır ve çıkış yapmadan hedef hesabın penceresine geçer")
            } else {
                Button {
                    viewModel.enableZeroLogoutDualProfileQuick()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "macwindow.on.rectangle")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("Çıkışsız Modu Aç")
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
                    .background(Capsule().fill(BridgeTheme.primaryAccent))
                }
                .buttonStyle(TactileScaleButtonStyle())
                .disabled(viewModel.isBusy)
                .help("2. profili oluşturup başlatır — bir kez giriş yaptıktan sonra çıkış/giriş olmadan otomatik geçiş çalışır")
            }

            Button {
                viewModel.syncAllActive(bidirectional: true)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 10.5, weight: .semibold))
                    Text("Tümünü Eşitle")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                    if viewModel.pendingBidirectionalCount > 0 {
                        Text("\(viewModel.pendingBidirectionalCount)")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.primary.opacity(0.10)))
                            .foregroundStyle(.primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 31, maxHeight: 31)
                .liquidGlassCapsule(tint: nil, interactive: false)
            }
            .buttonStyle(TactileScaleButtonStyle())
            .disabled(viewModel.isBusy || viewModel.accounts.count < 2)
            .help("İki hesap arasındaki arşivlenmemiş tüm oturumları çift yönlü eşitler")

            Button {
                viewModel.updateSettings { $0.autoSwitchEnabled.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.settings.autoSwitchEnabled ? "bolt.fill" : "bolt.slash")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(viewModel.settings.autoSwitchEnabled ? Color(nsColor: .systemGreen) : .secondary)
                    Text(isWideLayout ? "Oto Geçiş" : "Oto")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(viewModel.settings.autoSwitchEnabled ? .primary : .secondary)
                }
                .padding(.horizontal, 11)
                .frame(minHeight: 31, maxHeight: 31)
                .liquidGlassCapsule(
                    tint: viewModel.settings.autoSwitchEnabled ? Color(nsColor: .systemGreen) : nil,
                    interactive: false
                )
            }
            .buttonStyle(TactileScaleButtonStyle())
            .help(
                viewModel.settings.autoSwitchEnabled
                    ? "Otomatik limit geçişi AÇIK (\(viewModel.settings.autoSwitchTrigger.title))"
                    : "Otomatik limit geçişi KAPALI"
            )

            Button {
                if let secondary = viewModel.settings.secondaryProfiles.first {
                    viewModel.focusOrLaunchProfile(secondary)
                } else {
                    viewModel.reloadDefaultClaudeDesktop()
                }
            } label: {
                Image(systemName: viewModel.settings.secondaryProfiles.isEmpty ? "arrow.clockwise" : "macwindow")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.85))
                    .frame(width: 31, height: 31)
                    .liquidGlassCapsule(tint: nil, interactive: false)
            }
            .buttonStyle(TactileScaleButtonStyle())
            .disabled(viewModel.isBusy)
            .help(
                viewModel.settings.secondaryProfiles.isEmpty
                    ? "Claude Desktop'ı güvenle yenile"
                    : "2. Profil Claude Desktop penceresini aç / öne al"
            )
        }
    }

    // MARK: - Search & Filter Row

    private var searchAndFilterRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("Oturum veya proje ara...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                if !viewModel.searchText.isEmpty {
                    Button {
                        viewModel.searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 29, maxHeight: 29)
            .liquidGlassCapsule(tint: nil, interactive: false)

            LiquidGlassSegmentedControl(
                items: SessionFilter.allCases,
                selection: $viewModel.filter,
                title: { filter in
                    switch filter {
                    case .all: return "Tümü"
                    case .needsSync: return "Yeni"
                    case .live: return "Canlı"
                    case .archived: return "Arşiv"
                    }
                },
                compact: true
            )
            .frame(width: isWideLayout ? 260 : 224)
        }
    }

    // MARK: - 120Hz Session List

    private var sessionListSection: some View {
        let sessions = viewModel.filteredSourceSessions
        return Group {
            if sessions.isEmpty {
                VStack(spacing: 6) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Bu filtrede oturum bulunamadı")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 5) {
                        ForEach(sessions) { session in
                            SessionRowView(
                                session: session,
                                relation: viewModel.relation(for: session),
                                isJustTransferred: viewModel.recentlyTransferredIds.contains(session.sessionId),
                                isCrossProfile: viewModel.isCrossProfileMode,
                                isBusy: viewModel.isBusy,
                                targetName: viewModel.targetAccount?.displayName,
                                onTransfer: { switchAfter in
                                    viewModel.transferSession(session, switchToTargetAfter: switchAfter)
                                },
                                onCopyResume: {
                                    viewModel.copyResumeCommand(for: session)
                                },
                                onRevealFinder: {
                                    viewModel.revealProjectInFinder(session)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, hPad)
                    .padding(.bottom, isWideLayout ? 14 : 4)
                    .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, minHeight: 240, maxHeight: .infinity)
            }
        }
        .layoutPriority(1)
    }

    // MARK: - Status Banner

    private func statusBannerView(_ banner: StatusBanner) -> some View {
        let accent: Color = {
            switch banner.kind {
            case .success: return Color(nsColor: .systemGreen)
            case .info: return Color(nsColor: .systemBlue)
            case .warning: return Color(nsColor: .systemOrange)
            case .error: return Color(nsColor: .systemRed)
            }
        }()

        let iconName: String = {
            switch banner.kind {
            case .success: return "checkmark.circle.fill"
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.octagon.fill"
            }
        }()

        return HStack(alignment: .center, spacing: 9) {
            Image(systemName: iconName)
                .foregroundStyle(accent)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 1.5) {
                Text(banner.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                if let detail = banner.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 4)

            if let action = banner.quickAction {
                Button {
                    viewModel.executeBannerQuickAction(action)
                } label: {
                    Text(bannerActionLabel(action))
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(accent))
                        .foregroundStyle(.white)
                }
                .buttonStyle(TactileScaleButtonStyle())
                .disabled(viewModel.isBusy)
            }

            Button {
                viewModel.statusBanner = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .liquidGlassCard(
            cornerRadius: 11,
            tint: accent,
            strokeAccent: accent.opacity(0.32)
        )
    }

    private func bannerActionLabel(_ action: StatusBanner.QuickAction) -> String {
        switch action {
        case .reloadDefaultClaude: return "Yenile"
        case .launchOrReloadTargetProfile(_, let label): return label
        case .setupDualProfile: return "2. Profili Aç"
        case .openBackups: return "Yedekler"
        }
    }

    private var emptyAccountsView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.2.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("Claude Desktop oturum klasörü bulunamadı")
                .font(.system(size: 13, weight: .semibold))
            Text("~/Library/Application Support/Claude/claude-code-sessions altında hesap verisi algılanmadı.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            Button("Tekrar Tara") {
                viewModel.refresh(userInitiated: true)
            }
            .nativeGlassButton(prominent: true)
            .controlSize(.small)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Zero-Overhead 120Hz Session Row

struct SessionRowView: View {
    @Environment(\.colorScheme) private var scheme

    let session: ClaudeSessionCard
    let relation: SyncRelation
    let isJustTransferred: Bool
    let isCrossProfile: Bool
    let isBusy: Bool
    let targetName: String?
    let onTransfer: (Bool) -> Void
    let onCopyResume: () -> Void
    let onRevealFinder: () -> Void

    @State private var isHovered = false

    var body: some View {
        let isDark = (scheme == .dark)
        let rowBg: Color = {
            if session.isLiveRunning {
                return Color(nsColor: .systemGreen).opacity(isDark ? (isHovered ? 0.14 : 0.09) : (isHovered ? 0.11 : 0.07))
            }
            if isHovered {
                return isDark ? Color.white.opacity(0.095) : Color.white.opacity(0.84)
            }
            return isDark ? Color.white.opacity(0.05) : Color.white.opacity(0.60)
        }()

        let rowBorder: Color = {
            if session.isLiveRunning {
                return Color(nsColor: .systemGreen).opacity(0.30)
            }
            return isDark
                ? Color.white.opacity(isHovered ? 0.16 : 0.09)
                : Color.black.opacity(isHovered ? 0.12 : 0.07)
        }()

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 6) {
                    if session.isLiveRunning {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color(nsColor: .systemGreen))
                                .frame(width: 5, height: 5)
                            Text("CANLI")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Color(nsColor: .systemGreen))
                        }
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color(nsColor: .systemGreen).opacity(0.14)))
                    }

                    Text(session.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .help(session.title)
                }

                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8.5))
                        .foregroundStyle(.tertiary)
                    Text(session.projectName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if session.isWorktree {
                        Text("WT")
                            .font(.system(size: 8, weight: .bold))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 0.5)
                            .background(Capsule().fill(Color(nsColor: .systemOrange).opacity(0.16)))
                            .foregroundStyle(Color(nsColor: .systemOrange))
                    }

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text("\(session.completedTurns) tur")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)

                    if let size = session.formattedTranscriptSize {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(size)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Text("·")
                        .foregroundStyle(.quaternary)

                    Text(TurkishDateFormatter.relativeString(from: session.effectiveTimestamp))
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                relationPill

                Button {
                    onTransfer(isCrossProfile)
                } label: {
                    HStack(spacing: 3.5) {
                        Image(
                            systemName: isJustTransferred
                                ? "checkmark"
                                : (isCrossProfile ? "arrow.right.circle.fill" : "arrow.right")
                        )
                        .font(.system(size: 9.5, weight: .bold))
                        Text(isJustTransferred ? "Tamam" : (isCrossProfile ? "Geç" : "Aktar"))
                            .font(.system(size: 10.5, weight: .semibold))
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4.5)
                    .foregroundStyle(
                        isJustTransferred || relation.needsTransferToTarget ? .white : .primary
                    )
                    .background {
                        if isJustTransferred {
                            Capsule().fill(Color(nsColor: .systemGreen))
                        } else if relation.needsTransferToTarget {
                            Capsule().fill(BridgeTheme.primaryAccent)
                        } else {
                            Capsule().fill(Color.primary.opacity(0.09))
                        }
                    }
                }
                .buttonStyle(TactileScaleButtonStyle())
                .disabled(isBusy || targetName == nil)
                .help("Bu oturumu \(targetName ?? "hedef hesaba") aktar")

                Menu {
                    Button("Sadece Kartı Hedefe Aktar") {
                        onTransfer(false)
                    }
                    .disabled(targetName == nil)

                    if isCrossProfile {
                        Button("Aktar ve Hedef Profile Geç") {
                            onTransfer(true)
                        }
                    }

                    Divider()

                    if session.cliResumeCommand != nil {
                        Button("Terminal `claude --resume` Komutunu Kopyala") {
                            onCopyResume()
                        }
                    }

                    if !session.cwd.isEmpty {
                        Button("Proje Klasörünü Finder'da Göster") {
                            onRevealFinder()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(isHovered ? Color.primary.opacity(0.10) : .clear))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8.5)
        .background(
            RoundedRectangle(cornerRadius: BridgeTheme.innerRadius, style: .continuous)
                .fill(rowBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: BridgeTheme.innerRadius, style: .continuous)
                .strokeBorder(rowBorder, lineWidth: 0.75)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    @ViewBuilder
    private var relationPill: some View {
        switch relation {
        case .onlyInSource:
            badge("Yeni", Color(nsColor: .systemBlue))
        case .sourceNewer(let delta):
            badge(delta > 0 ? "+\(delta) tur" : "Güncelle", Color(nsColor: .systemOrange))
        case .inSync:
            badge("Eşit", Color(nsColor: .systemGreen))
        case .targetNewer(let delta):
            badge(delta > 0 ? "Hedef +\(delta)" : "Hedef Yeni", Color.secondary)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .padding(.horizontal, 6)
            .padding(.vertical, 2.5)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
            .fixedSize()
    }
}
