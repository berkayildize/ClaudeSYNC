import AppKit
import ClaudeSYNCCore
import Combine
import Foundation
import SwiftUI

enum SessionFilter: String, CaseIterable, Identifiable {
    case all = "Tümü"
    case needsSync = "Aktarılacak"
    case live = "Canlı"
    case archived = "Arşiv"

    var id: String { rawValue }
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case sessions = "Oturumlar"
    case limits = "Limitler"
    case settings = "Ayarlar"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack.fill"
        case .limits: return "gauge.with.dots.needle.67percent"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum MainAppSection: String, CaseIterable, Identifiable {
    case sessions = "Oturumlar"
    case limits = "Limitler"
    case profiles = "Profiller"
    case settings = "Ayarlar"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack.fill"
        case .limits: return "gauge.with.dots.needle.67percent"
        case .profiles: return "macwindow.on.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}

struct StatusBanner: Equatable {
    enum Kind {
        case success
        case info
        case warning
        case error
    }

    enum QuickAction: Equatable {
        case reloadDefaultClaude
        case launchOrReloadTargetProfile(accountId: String, label: String)
        case setupDualProfile
        case openBackups(URL)
    }

    let kind: Kind
    let title: String
    let detail: String?
    let quickAction: QuickAction?
}

struct AutoSwitchLogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let reason: String
    let targetName: String
    let transferredCount: Int
    let switchedWindow: Bool
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var accounts: [AccountSlot] = []
    @Published var settings: BridgeSettings
    @Published var processSnapshot: ProcessSnapshot = .empty
    @Published var sourceAccountId: String?
    @Published var targetAccountId: String?
    @Published var searchText: String = ""
    @Published var filter: SessionFilter = .all
    @Published var activeTab: PopoverTab = .sessions
    @Published var mainSection: MainAppSection = .sessions
    @Published var isRefreshing: Bool = false
    @Published var isBusy: Bool = false
    @Published var isSwitchingNow: Bool = false
    @Published var lastRefreshedAt: Date?
    @Published var statusBanner: StatusBanner?
    @Published var launchAtLogin: Bool = false
    @Published var showMenuBarExtra: Bool = true
    @Published var recentlyTransferredIds: Set<String> = []
    @Published var autoSwitchHistory: [AutoSwitchLogEntry] = []
    @Published private(set) var relationsBySessionId: [String: SyncRelation] = [:]
    @Published private(set) var cachedPendingBidirectionalCount: Int = 0
    @Published private(set) var autoCardSyncTotalCount: Int = 0
    @Published private(set) var lastAutoCardSyncAt: Date?
    @Published private(set) var appearanceTick: Int = 0

    var openMainWindowAction: (() -> Void)?

    private let preferencesStore: PreferencesStore
    private let discovery: SessionDiscovery
    private let processMonitor: ProcessMonitor
    private let syncEngine: SessionSyncEngine
    private let rateLimitWatcher: RateLimitWatcher
    private let launchAgent: LaunchAgentManager
    private var timer: Timer?
    private var themeObserver: NSObjectProtocol?
    private var refreshInFlight: Bool = false
    private var isDemoMode: Bool = false

    init(
        preferencesStore: PreferencesStore = PreferencesStore(),
        discovery: SessionDiscovery = SessionDiscovery(),
        processMonitor: ProcessMonitor = ProcessMonitor(),
        syncEngine: SessionSyncEngine = SessionSyncEngine(),
        rateLimitWatcher: RateLimitWatcher = RateLimitWatcher(),
        launchAgent: LaunchAgentManager = LaunchAgentManager()
    ) {
        self.preferencesStore = preferencesStore
        self.discovery = discovery
        self.processMonitor = processMonitor
        self.syncEngine = syncEngine
        self.rateLimitWatcher = rateLimitWatcher
        self.launchAgent = launchAgent

        let loaded = preferencesStore.load()
        self.settings = loaded
        self.sourceAccountId = loaded.selectedSourceAccountId
        self.targetAccountId = loaded.selectedTargetAccountId
        self.showMenuBarExtra = loaded.showMenuBarExtra
        self.launchAtLogin = launchAgent.isEnabled

        NotificationHelper.shared.requestPermissionIfNeeded()
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.appearanceTick &+= 1
            }
        }
        self.isDemoMode = CommandLine.arguments.contains("--demo-snapshot")
        if !self.isDemoMode {
            refresh()
            startAutoRefresh()
        }
    }

    deinit {
        timer?.invalidate()
        if let obs = themeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }

    // MARK: - Computed Properties

    var sourceAccount: AccountSlot? {
        if let id = sourceAccountId, let match = accounts.first(where: { $0.id == id }) {
            return match
        }
        return accounts.first(where: { $0.isActiveAccount }) ?? accounts.first
    }

    var targetAccount: AccountSlot? {
        let srcId = sourceAccount?.id
        if let id = targetAccountId, id != srcId, let match = accounts.first(where: { $0.id == id }) {
            return match
        }
        return accounts.first(where: { $0.id != srcId })
    }

    var activeAccount: AccountSlot? {
        accounts.first(where: { $0.isActiveAccount }) ?? sourceAccount
    }

    var isCrossProfileMode: Bool {
        guard let src = sourceAccount, let dst = targetAccount else { return false }
        return src.profileDataDir.standardizedFileURL != dst.profileDataDir.standardizedFileURL
    }

    var hasSecondaryProfileConfigured: Bool {
        !settings.secondaryProfiles.isEmpty
    }

    var liveSessionCount: Int {
        processSnapshot.liveCliSessionIds.count
    }

    var menuBarImage: NSImage {
        _ = appearanceTick
        return MenuBarWidgetRenderer.shared.image(
            mode: settings.menuBarDisplayMode,
            accounts: accounts,
            activeAccount: activeAccount,
            isSwitching: isSwitchingNow
        )
    }

    var filteredSourceSessions: [ClaudeSessionCard] {
        guard let src = sourceAccount else { return [] }

        let base: [ClaudeSessionCard]
        switch filter {
        case .all:
            base = src.activeSessions
        case .live:
            base = src.liveSessions
        case .archived:
            base = src.sessions.filter { $0.isArchived || src.archivedIds.contains($0.sessionId) }
        case .needsSync:
            if targetAccount != nil {
                base = src.activeSessions.filter { relation(for: $0).needsTransferToTarget }
            } else {
                base = src.activeSessions
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return base }
        return base.filter {
            $0.title.lowercased().contains(query) ||
            $0.projectName.lowercased().contains(query) ||
            $0.cwd.lowercased().contains(query)
        }
    }

    var pendingBidirectionalCount: Int {
        cachedPendingBidirectionalCount
    }

    func relation(for session: ClaudeSessionCard) -> SyncRelation {
        relationsBySessionId[session.sessionId] ?? .onlyInSource
    }

    private func recomputeRelationCaches() {
        guard let src = sourceAccount, let dst = targetAccount else {
            if !relationsBySessionId.isEmpty { relationsBySessionId = [:] }
            if cachedPendingBidirectionalCount != 0 { cachedPendingBidirectionalCount = 0 }
            return
        }
        var map: [String: SyncRelation] = [:]
        map.reserveCapacity(src.sessions.count)
        for s in src.sessions {
            map[s.sessionId] = syncEngine.computeRelation(session: s, in: dst)
        }
        let aToB = src.activeSessions.filter { map[$0.sessionId]?.needsTransferToTarget == true }.count
        let bToA = dst.activeSessions.filter { syncEngine.computeRelation(session: $0, in: src).needsTransferToTarget }.count
        let total = aToB + bToA

        if relationsBySessionId != map { relationsBySessionId = map }
        if cachedPendingBidirectionalCount != total { cachedPendingBidirectionalCount = total }
    }

    // MARK: - Menu Bar Visibility Control

    func setShowMenuBarExtra(_ show: Bool) {
        showMenuBarExtra = show
        settings.showMenuBarExtra = show
        preferencesStore.save(settings)
        if !show {
            NSApp.setActivationPolicy(.regular)
            openMainWindow()
        }
    }

    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        openMainWindowAction?()
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Refresh & Background Auto-Sync Loop

    func startAutoRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(userInitiated: false)
            }
        }
    }

    func refresh(userInitiated: Bool = true) {
        guard !isDemoMode, !refreshInFlight else { return }
        refreshInFlight = true
        if userInitiated {
            isRefreshing = true
        }

        let profiles = settings.allProfiles
        let nicknames = settings.accountNicknames
        let isSnapshot = CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--demo-snapshot")
        let shouldAutoSyncCards = settings.autoSyncSharedCards && !isSnapshot
        let transferOpts = settings.transferOptions
        let disc = discovery
        let mon = processMonitor
        let engine = syncEngine

        Task.detached(priority: userInitiated ? .userInitiated : .utility) {
            let snap = mon.captureSnapshot()
            var discovered = disc.discoverAccounts(
                profiles: profiles,
                nicknames: nicknames,
                processSnapshot: snap
            )

            var syncedCount = 0
            if shouldAutoSyncCards && discovered.count >= 2 {
                let first = discovered[0]
                for other in discovered.dropFirst() {
                    if let summary = try? engine.syncSharedCards(
                        between: first,
                        and: other,
                        liveCliSessionIds: snap.liveCliSessionIds,
                        options: transferOpts
                    ) {
                        syncedCount += summary.updatedCount
                    }
                }
                if syncedCount > 0 {
                    discovered = disc.discoverAccounts(
                        profiles: profiles,
                        nicknames: nicknames,
                        processSnapshot: snap
                    )
                }
            }

            let finalDiscovered = discovered
            let finalSyncedCount = syncedCount
            await MainActor.run { [weak self] in
                guard let self else { return }
                let snapChanged = self.processSnapshot != snap
                let accountsChanged = self.accounts != finalDiscovered
                if snapChanged { self.processSnapshot = snap }
                if accountsChanged { self.accounts = finalDiscovered }
                if finalSyncedCount > 0 {
                    self.autoCardSyncTotalCount += finalSyncedCount
                    self.lastAutoCardSyncAt = Date()
                }
                if accountsChanged || self.sourceAccountId == nil || self.targetAccountId == nil {
                    self.reconcileAccountSelection()
                    self.recomputeRelationCaches()
                }
                if userInitiated || self.lastRefreshedAt == nil || accountsChanged {
                    self.lastRefreshedAt = Date()
                }
                self.refreshInFlight = false
                if self.isRefreshing { self.isRefreshing = false }
                if !isSnapshot {
                    self.checkAutoSwitchIfNeeded()
                }
            }
        }
    }

    private func reconcileAccountSelection() {
        let ids = Set(accounts.map(\.id))
        if sourceAccountId == nil || !ids.contains(sourceAccountId!) {
            sourceAccountId = (accounts.first(where: { $0.isActiveAccount }) ?? accounts.first)?.id
        }
        if targetAccountId == nil || !ids.contains(targetAccountId!) || targetAccountId == sourceAccountId {
            targetAccountId = accounts.first(where: { $0.id != sourceAccountId })?.id
        }
    }

    private func checkAutoSwitchIfNeeded() {
        guard !isBusy, !isSwitchingNow else { return }
        guard let decision = rateLimitWatcher.evaluateAutoSwitch(
            accounts: accounts,
            settings: settings,
            lastHandledEventKey: settings.lastAutoSwitchEventKey
        ) else { return }

        executeAutoSwitch(decision)
    }

    private func executeAutoSwitch(_ decision: AutoSwitchDecision) {
        settings.lastAutoSwitchEventKey = decision.eventKey
        preferencesStore.save(settings)

        isSwitchingNow = true
        isBusy = true

        let opts = settings.transferOptions
        let engine = syncEngine
        let mon = processMonitor
        let notify = settings.autoSwitchNotify

        Task {
            var transferred = 0
            for session in decision.sessionsToTransfer {
                if (try? engine.transferSession(session, from: decision.source, to: decision.target, options: opts)) != nil {
                    transferred += 1
                }
            }

            var switchedWindow = false
            if decision.isZeroLogoutReady {
                do {
                    if let pid = decision.target.runningPid {
                        try await mon.gracefulRestart(
                            pid: pid,
                            dataDir: decision.target.profileDataDir,
                            isDefault: decision.target.isDefaultProfile
                        )
                    } else {
                        try mon.launchProfile(
                            dataDir: decision.target.profileDataDir,
                            isDefault: decision.target.isDefaultProfile
                        )
                    }
                    switchedWindow = true
                } catch {
                    switchedWindow = false
                }
            }

            self.isSwitchingNow = false
            self.isBusy = false
            self.sourceAccountId = decision.target.id
            self.targetAccountId = decision.source.id
            self.recomputeRelationCaches()
            self.persistSelection()

            let entry = AutoSwitchLogEntry(
                timestamp: Date(),
                reason: decision.reason,
                targetName: decision.target.displayName,
                transferredCount: transferred,
                switchedWindow: switchedWindow
            )
            self.autoSwitchHistory.insert(entry, at: 0)

            let title = switchedWindow
                ? "Otomatik Geçiş Tamamlandı → \(decision.target.displayName)"
                : "Limit Doldu · \(transferred) Oturum \(decision.target.displayName) Hesabına Aktarıldı"
            let detail = switchedWindow
                ? "\(decision.reason). \(transferred) oturum taşındı ve \(decision.target.displayName) penceresi açıldı."
                : "\(decision.reason). Çıkışsız pencere geçişi için 2. profili etkinleştirebilirsiniz."

            self.statusBanner = StatusBanner(
                kind: .success,
                title: title,
                detail: detail,
                quickAction: decision.isZeroLogoutReady ? nil : .setupDualProfile
            )

            if notify {
                NotificationHelper.shared.send(title: title, body: detail)
            }

            self.refresh()
        }
    }

    // MARK: - Instant 1-Click Manual Switch

    func instantSwitchToTarget() {
        guard let src = sourceAccount, let dst = targetAccount else { return }
        let sessionsToMove: [ClaudeSessionCard]
        if settings.autoSwitchTransferAllLive && !src.liveSessions.isEmpty {
            sessionsToMove = src.liveSessions
        } else if let top = src.liveSessions.first ?? src.activeSessions.first {
            sessionsToMove = [top]
        } else {
            sessionsToMove = []
        }

        let crossProfile = src.profileDataDir.standardizedFileURL != dst.profileDataDir.standardizedFileURL
        isSwitchingNow = true
        isBusy = true

        let opts = settings.transferOptions
        let engine = syncEngine
        let mon = processMonitor

        Task {
            var movedIds: [String] = []
            for s in sessionsToMove {
                if (try? engine.transferSession(s, from: src, to: dst, options: opts)) != nil {
                    movedIds.append(s.sessionId)
                }
            }

            if crossProfile {
                do {
                    if let pid = dst.runningPid {
                        try await mon.gracefulRestart(
                            pid: pid,
                            dataDir: dst.profileDataDir,
                            isDefault: dst.isDefaultProfile
                        )
                    } else {
                        try mon.launchProfile(dataDir: dst.profileDataDir, isDefault: dst.isDefaultProfile)
                    }
                    self.sourceAccountId = dst.id
                    self.targetAccountId = src.id
                    self.recomputeRelationCaches()
                    self.persistSelection()
                    self.statusBanner = StatusBanner(
                        kind: .success,
                        title: "\(dst.displayName) hesabına geçiş yapıldı",
                        detail: "\(movedIds.count) aktif oturum en üste taşındı — çıkış yapmadan devam edebilirsiniz.",
                        quickAction: nil
                    )
                } catch {
                    self.statusBanner = StatusBanner(
                        kind: .warning,
                        title: "\(movedIds.count) oturum aktarıldı, pencere açılamadı",
                        detail: error.localizedDescription,
                        quickAction: .launchOrReloadTargetProfile(accountId: dst.id, label: "Tekrar Dene")
                    )
                }
            } else {
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: "\(movedIds.count) oturum \(dst.displayName) hesabına aktarıldı",
                    detail: "Çıkış/giriş yapmadan tek tıkla geçiş için Çift Profil modunu etkinleştirin.",
                    quickAction: .setupDualProfile
                )
            }

            for id in movedIds {
                self.markRecentlyTransferred(id)
            }

            self.isSwitchingNow = false
            self.isBusy = false
            self.refresh()
        }
    }

    // MARK: - Account Selection & Nicknames

    func selectSource(_ accountId: String) {
        if targetAccountId == accountId {
            targetAccountId = sourceAccountId
        }
        sourceAccountId = accountId
        recomputeRelationCaches()
        persistSelection()
    }

    func selectTarget(_ accountId: String) {
        if sourceAccountId == accountId {
            sourceAccountId = targetAccountId
        }
        targetAccountId = accountId
        recomputeRelationCaches()
        persistSelection()
    }

    func swapAccounts() {
        guard let src = sourceAccount?.id, let dst = targetAccount?.id else { return }
        sourceAccountId = dst
        targetAccountId = src
        recomputeRelationCaches()
        persistSelection()
    }

    private func persistSelection() {
        settings.selectedSourceAccountId = sourceAccountId
        settings.selectedTargetAccountId = targetAccountId
        preferencesStore.save(settings)
    }

    func updateNickname(for account: AccountSlot, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            settings.accountNicknames.removeValue(forKey: account.accountOrgKey)
        } else {
            settings.accountNicknames[account.accountOrgKey] = trimmed
        }
        preferencesStore.save(settings)
        refresh()
    }

    func updateSettings(_ mutate: (inout BridgeSettings) -> Void) {
        mutate(&settings)
        showMenuBarExtra = settings.showMenuBarExtra
        preferencesStore.save(settings)
        refresh(userInitiated: false)
    }

    // MARK: - Single Session & Batch Transfer

    func transferSession(_ session: ClaudeSessionCard, switchToTargetAfter: Bool = false) {
        guard let src = sourceAccount, let dst = targetAccount else {
            statusBanner = StatusBanner(
                kind: .warning,
                title: "Hedef hesap bulunamadı",
                detail: "Aktarım için en az 2 farklı hesap veya profil algılanmalıdır.",
                quickAction: nil
            )
            return
        }

        isBusy = true
        let opts = settings.transferOptions
        let engine = syncEngine

        Task.detached(priority: .userInitiated) {
            do {
                let res = try engine.transferSession(session, from: src, to: dst, options: opts)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isBusy = false
                    self.markRecentlyTransferred(session.sessionId)
                    self.refresh()

                    var detailParts: [String] = ["\(res.sourceName) → \(res.targetName)"]
                    if !res.notes.isEmpty {
                        detailParts.append(res.notes.joined(separator: " · "))
                    }
                    if session.isLiveRunning {
                        detailParts.append("Not: Bu oturum şu an açık — üretim bittikten sonra diğer hesapta devam edin.")
                    }

                    let quickAction: StatusBanner.QuickAction
                    if res.wasCrossProfile {
                        let label = dst.runningPid != nil ? "\(dst.displayName) Profilini Yenile" : "\(dst.displayName) Profilini Aç"
                        quickAction = .launchOrReloadTargetProfile(accountId: dst.id, label: label)
                    } else {
                        quickAction = .reloadDefaultClaude
                    }

                    self.statusBanner = StatusBanner(
                        kind: .success,
                        title: "\"\(res.title)\" aktarıldı",
                        detail: detailParts.joined(separator: "\n"),
                        quickAction: quickAction
                    )

                    if switchToTargetAfter && res.wasCrossProfile {
                        self.launchOrReloadProfile(forAccountId: dst.id)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isBusy = false
                    self?.statusBanner = StatusBanner(
                        kind: .error,
                        title: "Aktarım başarısız",
                        detail: error.localizedDescription,
                        quickAction: nil
                    )
                }
            }
        }
    }

    private func markRecentlyTransferred(_ sessionId: String) {
        recentlyTransferredIds.insert(sessionId)
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            recentlyTransferredIds.remove(sessionId)
        }
    }

    func syncAllActive(bidirectional: Bool = true) {
        guard let src = sourceAccount, let dst = targetAccount else { return }
        isBusy = true
        let opts = settings.transferOptions
        let engine = syncEngine

        Task.detached(priority: .userInitiated) {
            do {
                let summary = try engine.syncAllActive(
                    from: src,
                    to: dst,
                    bidirectional: bidirectional,
                    options: opts
                )
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isBusy = false
                    self.refresh()

                    if !summary.errors.isEmpty {
                        self.statusBanner = StatusBanner(
                            kind: .warning,
                            title: "Eşitleme kısmen tamamlandı (\(summary.totalChanged) güncellendi)",
                            detail: summary.errors.prefix(2).joined(separator: "\n"),
                            quickAction: summary.backupDir.map { .openBackups($0) }
                        )
                    } else if summary.totalChanged == 0 {
                        self.statusBanner = StatusBanner(
                            kind: .info,
                            title: "Tüm aktif oturumlar zaten güncel",
                            detail: "\(summary.skippedUpToDate) oturum iki hesapta da eşit durumda.",
                            quickAction: nil
                        )
                    } else {
                        let crossProfile = src.profileDataDir.standardizedFileURL != dst.profileDataDir.standardizedFileURL
                        let action: StatusBanner.QuickAction = crossProfile
                            ? .launchOrReloadTargetProfile(accountId: dst.id, label: "\(dst.displayName) Profilini Yenile")
                            : .reloadDefaultClaude
                        self.statusBanner = StatusBanner(
                            kind: .success,
                            title: "Eşitleme tamamlandı: \(summary.copiedCount) yeni, \(summary.updatedCount) güncellendi",
                            detail: "\(summary.skippedUpToDate) oturum zaten günceldi.",
                            quickAction: action
                        )
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.isBusy = false
                    self?.statusBanner = StatusBanner(
                        kind: .error,
                        title: "Toplu eşitleme hatası",
                        detail: error.localizedDescription,
                        quickAction: nil
                    )
                }
            }
        }
    }

    // MARK: - Profile & Claude Desktop Control

    func executeBannerQuickAction(_ action: StatusBanner.QuickAction) {
        switch action {
        case .reloadDefaultClaude:
            reloadDefaultClaudeDesktop()
        case .launchOrReloadTargetProfile(let accountId, _):
            launchOrReloadProfile(forAccountId: accountId)
        case .setupDualProfile:
            enableZeroLogoutDualProfileQuick()
        case .openBackups(let dir):
            NSWorkspace.shared.open(dir)
        }
    }

    func enableZeroLogoutDualProfileQuick() {
        let suggested = ProfileConfig.suggestedSecondaryProfile
        let accountToMigrate = targetAccount ?? accounts.last
        setupAndLaunchSecondaryProfile(
            name: suggested.name,
            path: suggested.dataDirPath,
            copyMcpConfig: true,
            migrateAccount: accountToMigrate
        )
    }

    func reloadDefaultClaudeDesktop() {
        let defaultDir = ProfileConfig.defaultProfile.expandedURL
        let runningPid = processSnapshot.runningInstances.first(where: { $0.isDefaultProfile })?.pid
        isBusy = true
        let mon = processMonitor

        Task {
            do {
                try await mon.gracefulRestart(pid: runningPid, dataDir: defaultDir, isDefault: true)
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: "Claude Desktop yeniden başlatıldı",
                    detail: "Kenar çubuğu aktarılan oturumlarla yenilendi.",
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: "Yenileme tamamlanamadı",
                    detail: error.localizedDescription,
                    quickAction: nil
                )
            }
        }
    }

    func launchOrReloadProfile(forAccountId accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        let mon = processMonitor
        isBusy = true

        Task {
            do {
                if let pid = account.runningPid {
                    try await mon.gracefulRestart(
                        pid: pid,
                        dataDir: account.profileDataDir,
                        isDefault: account.isDefaultProfile
                    )
                } else {
                    try mon.launchProfile(dataDir: account.profileDataDir, isDefault: account.isDefaultProfile)
                }
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: "\(account.displayName) açıldı",
                    detail: "Aktarılan oturum kenar çubuğunun en üstünde hazır.",
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: "Profil başlatılamadı",
                    detail: error.localizedDescription,
                    quickAction: nil
                )
            }
        }
    }

    func focusOrLaunchProfile(_ profile: ProfileConfig) {
        let dir = profile.expandedURL.standardizedFileURL
        if let running = processSnapshot.runningInstances.first(where: {
            $0.dataDir == dir.path || (profile.isDefault && $0.isDefaultProfile)
        }) {
            _ = processMonitor.activateInstance(pid: running.pid)
        } else {
            do {
                try processMonitor.launchProfile(dataDir: dir, isDefault: profile.isDefault)
                statusBanner = StatusBanner(
                    kind: .info,
                    title: "\(profile.name) başlatılıyor",
                    detail: "Açılan pencerede hesabınız sürekli giriş yapılı kalır.",
                    quickAction: nil
                )
                refresh()
            } catch {
                statusBanner = StatusBanner(
                    kind: .error,
                    title: "Profil başlatılamadı",
                    detail: error.localizedDescription,
                    quickAction: nil
                )
            }
        }
    }

    func reloadProfile(_ profile: ProfileConfig) {
        let dir = profile.expandedURL.standardizedFileURL
        let runningPid = processSnapshot.runningInstances.first(where: {
            $0.dataDir == dir.path || (profile.isDefault && $0.isDefaultProfile)
        })?.pid
        let mon = processMonitor
        isBusy = true

        Task {
            do {
                try await mon.gracefulRestart(pid: runningPid, dataDir: dir, isDefault: profile.isDefault)
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: "\(profile.name) yeniden başlatıldı",
                    detail: "Kenar çubuğu güncel oturumlarla yenilendi.",
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: "Profil yenilenemedi",
                    detail: error.localizedDescription,
                    quickAction: nil
                )
            }
        }
    }

    func runningInstance(for profile: ProfileConfig) -> RunningClaudeInstance? {
        let std = profile.expandedURL.standardizedFileURL.path
        return processSnapshot.runningInstances.first {
            $0.dataDir == std || (profile.isDefault && $0.isDefaultProfile)
        }
    }

    func setupAndLaunchSecondaryProfile(
        name: String,
        path: String,
        copyMcpConfig: Bool,
        migrateAccount: AccountSlot? = nil
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else { return }

        let profile = ProfileConfig(
            id: "profile-\(UUID().uuidString.prefix(8))",
            name: trimmedName.isEmpty ? "2. Profil" : trimmedName,
            dataDirPath: trimmedPath,
            isDefault: false
        )

        do {
            let copiedMcp = try syncEngine.initializeSecondaryProfile(
                at: profile.expandedURL,
                copyMcpConfigFrom: copyMcpConfig ? ProfileConfig.defaultProfile.expandedURL : nil,
                migrateAccountSessionsFrom: migrateAccount
            )

            if !settings.secondaryProfiles.contains(where: {
                $0.expandedURL.standardizedFileURL.path == profile.expandedURL.standardizedFileURL.path
            }) {
                settings.secondaryProfiles.append(profile)
                preferencesStore.save(settings)
            }

            try processMonitor.launchProfile(dataDir: profile.expandedURL, isDefault: false)

            var extras: [String] = []
            if copiedMcp { extras.append("yerel MCP ayarları") }
            if let migrated = migrateAccount { extras.append("\(migrated.activeSessions.count) mevcut oturum") }
            let extraNote = extras.isEmpty ? "" : " (\(extras.joined(separator: " + ")) aktarıldı)"

            statusBanner = StatusBanner(
                kind: .success,
                title: "Çıkışsız 2. Profil Başlatıldı",
                detail: "Açılan pencerede 2. Ultra hesabınızla 1 kez giriş yapın; bundan sonra çıkış yapmadan otomatik geçiş çalışır.\(extraNote)",
                quickAction: nil
            )
            refresh()
        } catch {
            statusBanner = StatusBanner(
                kind: .error,
                title: "2. profil oluşturulamadı",
                detail: error.localizedDescription,
                quickAction: nil
            )
        }
    }

    func removeSecondaryProfile(_ profile: ProfileConfig) {
        settings.secondaryProfiles.removeAll { $0.id == profile.id }
        preferencesStore.save(settings)
        refresh()
    }

    // MARK: - Utilities

    func copyResumeCommand(for session: ClaudeSessionCard) {
        guard let cmd = session.cliResumeCommand else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd, forType: .string)
        statusBanner = StatusBanner(
            kind: .info,
            title: "CLI devam komutu kopyalandı",
            detail: cmd,
            quickAction: nil
        )
    }

    func revealProjectInFinder(_ session: ClaudeSessionCard) {
        guard !session.cwd.isEmpty else { return }
        let url = URL(fileURLWithPath: session.cwd)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func openBackupsFolder() {
        let dir = syncEngine.backupRootDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try launchAgent.setEnabled(enabled)
            launchAtLogin = launchAgent.isEnabled
        } catch {
            launchAtLogin = launchAgent.isEnabled
            statusBanner = StatusBanner(
                kind: .error,
                title: "Otomatik başlatma ayarlanamadı",
                detail: error.localizedDescription,
                quickAction: nil
            )
        }
    }

    // MARK: - Synthetic Open-Source Demo Data (strictly for --demo-snapshot screenshots)

    func loadSyntheticDemoData() {
        isDemoMode = true
        let now = Date()
        let fakeDir1 = URL(fileURLWithPath: "/Users/demo/Library/Application Support/Claude", isDirectory: true)
        let fakeDir2 = URL(fileURLWithPath: "/Users/demo/Library/Application Support/Claude-Account2", isDirectory: true)

        func makeCard(
            id: String,
            cli: String,
            title: String,
            cwd: String,
            turns: Int,
            minsAgo: Double,
            sizeMB: Int64,
            live: Bool = false
        ) -> ClaudeSessionCard {
            let ts = now.addingTimeInterval(-minsAgo * 60)
            return ClaudeSessionCard(
                sessionId: id,
                cliSessionId: cli,
                title: title,
                cwd: cwd,
                model: "claude-opus-4-6",
                completedTurns: turns,
                createdAt: ts.addingTimeInterval(-3600),
                lastActivityAt: ts,
                lastFocusedAt: ts,
                isArchived: false,
                filePath: fakeDir1.appendingPathComponent("\(id).json"),
                fileModDate: ts,
                transcriptPath: URL(fileURLWithPath: "/tmp/\(cli).jsonl"),
                transcriptSizeBytes: sizeMB * 1_048_576,
                isLiveRunning: live
            )
        }

        let acc1Sessions: [ClaudeSessionCard] = [
            makeCard(id: "local_demo1", cli: "cli-demo-1", title: "Realtime Voice Pipeline & WebRTC Audio", cwd: "/Users/demo/dev/voice-engine", turns: 142, minsAgo: 4, sizeMB: 184, live: true),
            makeCard(id: "local_demo2", cli: "cli-demo-2", title: "SwiftUI Native Menu Bar Architecture", cwd: "/Users/demo/dev/claudesync", turns: 64, minsAgo: 9, sizeMB: 72, live: true),
            makeCard(id: "local_demo3", cli: "cli-demo-3", title: "Stripe Billing Webhook Idempotency", cwd: "/Users/demo/dev/saas-api/.claude/worktrees/billing-v2", turns: 48, minsAgo: 18, sizeMB: 56),
            makeCard(id: "local_demo4", cli: "cli-demo-4", title: "Postgres Composite Index Migration", cwd: "/Users/demo/dev/saas-api", turns: 83, minsAgo: 42, sizeMB: 129),
            makeCard(id: "local_demo5", cli: "cli-demo-5", title: "iOS Push Notification Service Extension", cwd: "/Users/demo/dev/mobile-app", turns: 51, minsAgo: 95, sizeMB: 91),
            makeCard(id: "local_demo6", cli: "cli-demo-6", title: "MCP Server Tool Discovery & Caching", cwd: "/Users/demo/dev/mcp-kit", turns: 37, minsAgo: 180, sizeMB: 44),
            makeCard(id: "local_demo7", cli: "cli-demo-7", title: "End-to-End Playwright Checkout Suite", cwd: "/Users/demo/dev/web-store", turns: 29, minsAgo: 310, sizeMB: 38)
        ]

        let acc2Sessions: [ClaudeSessionCard] = [
            makeCard(id: "local_demo1", cli: "cli-demo-1", title: "Realtime Voice Pipeline & WebRTC Audio", cwd: "/Users/demo/dev/voice-engine", turns: 142, minsAgo: 4, sizeMB: 184),
            makeCard(id: "local_demo2", cli: "cli-demo-2", title: "SwiftUI Native Menu Bar Architecture", cwd: "/Users/demo/dev/claudesync", turns: 61, minsAgo: 15, sizeMB: 72),
            makeCard(id: "local_demo8", cli: "cli-demo-8", title: "Kubernetes Zero-Downtime Rollout", cwd: "/Users/demo/dev/infra", turns: 94, minsAgo: 55, sizeMB: 112),
            makeCard(id: "local_demo9", cli: "cli-demo-9", title: "Redis Rate Limiter Sliding Window", cwd: "/Users/demo/dev/edge-gateway", turns: 67, minsAgo: 140, sizeMB: 81)
        ]

        let history1: [UsageSamplePoint] = [12, 18, 25, 22, 30, 14, 8, 12, 16, 18].enumerated().map { idx, val in
            UsageSamplePoint(
                timestamp: now.addingTimeInterval(Double(idx - 10) * 3600 * 6),
                fiveHour: max(0, val - 6),
                sevenDay: val,
                extraUsage: nil
            )
        }
        let history2: [UsageSamplePoint] = [34, 48, 62, 71, 84, 91, 96, 100, 100].enumerated().map { idx, val in
            UsageSamplePoint(
                timestamp: now.addingTimeInterval(Double(idx - 9) * 3600 * 6),
                fiveHour: nil,
                sevenDay: val,
                extraUsage: 0
            )
        }

        let slot1 = AccountSlot(
            profileId: "default",
            profileName: "Ana Profil",
            profileDataDir: fakeDir1,
            isDefaultProfile: true,
            accountUuid: "a1b2c3d4-0000-4000-8000-000000000001",
            orgUuid: "11111111-0000-4000-8000-000000000001",
            sessionsDir: fakeDir1.appendingPathComponent("claude-code-sessions/a1/o1"),
            displayName: "Ultra 1",
            sessions: acc1Sessions,
            archivedIds: [],
            usage: OrgUsage(
                orgUuid: "11111111-0000-4000-8000-000000000001",
                fiveHourPercent: 12,
                sevenDayPercent: 18,
                extraUsagePercent: nil,
                updatedAt: now.addingTimeInterval(-120),
                history: history1,
                lastRateLimitHit: nil
            ),
            isActiveAccount: true,
            runningPid: 41205
        )

        let slot2 = AccountSlot(
            profileId: "secondary-account-2",
            profileName: "2. Profil",
            profileDataDir: fakeDir2,
            isDefaultProfile: false,
            accountUuid: "e5f6a7b8-0000-4000-8000-000000000002",
            orgUuid: "22222222-0000-4000-8000-000000000002",
            sessionsDir: fakeDir2.appendingPathComponent("claude-code-sessions/a2/o2"),
            displayName: "Ultra 2",
            sessions: acc2Sessions,
            archivedIds: [],
            usage: OrgUsage(
                orgUuid: "22222222-0000-4000-8000-000000000002",
                fiveHourPercent: nil,
                sevenDayPercent: 100,
                extraUsagePercent: 0,
                updatedAt: now.addingTimeInterval(-480),
                history: history2,
                lastRateLimitHit: RateLimitEvent(
                    timestamp: now.addingTimeInterval(-600),
                    rateLimitType: "seven_day",
                    resetsAt: now.addingTimeInterval(3600 * 52),
                    status: "rejected",
                    cliSessionId: "cli-demo-8"
                )
            ),
            isActiveAccount: false,
            runningPid: 41990
        )

        settings.secondaryProfiles = [
            ProfileConfig(id: "secondary-account-2", name: "2. Profil", dataDirPath: "~/Library/Application Support/Claude-Account2", isDefault: false)
        ]
        settings.autoSwitchEnabled = true
        settings.autoSyncSharedCards = true
        settings.showMenuBarExtra = true
        settings.menuBarDisplayMode = .iconAndBothAccounts
        showMenuBarExtra = true

        processSnapshot = ProcessSnapshot(
            runningInstances: [
                RunningClaudeInstance(pid: 41205, dataDir: fakeDir1.path, isDefaultProfile: true),
                RunningClaudeInstance(pid: 41990, dataDir: fakeDir2.path, isDefaultProfile: false)
            ],
            liveCliSessionIds: ["cli-demo-1", "cli-demo-2"],
            activeAccountOrgPairs: ["a1b2c3d4-0000-4000-8000-000000000001/11111111-0000-4000-8000-000000000001"]
        )
        accounts = [slot1, slot2]
        sourceAccountId = slot1.id
        targetAccountId = slot2.id
        lastRefreshedAt = now
        recomputeRelationCaches()
    }
}
