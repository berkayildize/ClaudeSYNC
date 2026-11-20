import AppKit
import ClaudeSYNCCore
import Combine
import Foundation
import SwiftUI

enum SessionFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case needsSync = "needsSync"
    case live = "live"
    case archived = "archived"

    var id: String { rawValue }

    func shortTitle(_ l10n: L10n) -> String {
        switch self {
        case .all: return l10n.t("Tümü", "All")
        case .needsSync: return l10n.t("Yeni", "Unsynced")
        case .live: return l10n.t("Canlı", "Live")
        case .archived: return l10n.t("Arşiv", "Archive")
        }
    }
}

enum PopoverTab: String, CaseIterable, Identifiable {
    case sessions = "sessions"
    case limits = "limits"
    case settings = "settings"

    var id: String { rawValue }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .sessions: return l10n.t("Oturumlar", "Sessions")
        case .limits: return l10n.t("Limitler", "Limits")
        case .settings: return l10n.t("Ayarlar", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack.fill"
        case .limits: return "gauge.with.dots.needle.67percent"
        case .settings: return "slider.horizontal.3"
        }
    }
}

enum MainAppSection: String, CaseIterable, Identifiable {
    case sessions = "sessions"
    case limits = "limits"
    case profiles = "profiles"
    case settings = "settings"

    var id: String { rawValue }

    func title(_ l10n: L10n) -> String {
        switch self {
        case .sessions: return l10n.t("Oturumlar", "Sessions")
        case .limits: return l10n.t("Limitler", "Limits")
        case .profiles: return l10n.t("Profiller", "Profiles")
        case .settings: return l10n.t("Ayarlar", "Settings")
        }
    }

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack.fill"
        case .limits: return "gauge.with.dots.needle.67percent"
        case .profiles: return "macwindow.on.rectangle"
        case .settings: return "gearshape.fill"
        }
    }
}

struct SetupDiagnostics: Equatable {
    var claudeAppInstalled: Bool = false
    var claudeDataDirAccessible: Bool = false
    var claudeProjectsAccessible: Bool = false
    var notificationStatus: NotificationPermissionState = .notDetermined
    var detectedAccountCount: Int = 0
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
    @Published var onboardingStep: OnboardingStep = .welcome
    @Published var isShowingOnboarding: Bool = false
    @Published var setupDiagnostics: SetupDiagnostics = SetupDiagnostics()
    @Published var recentlyTransferredIds: Set<String> = []
    @Published var autoSwitchHistory: [AutoSwitchLogEntry] = []
    @Published private(set) var relationsBySessionId: [String: SyncRelation] = [:]
    @Published private(set) var cachedPendingBidirectionalCount: Int = 0
    @Published private(set) var autoCardSyncTotalCount: Int = 0
    @Published private(set) var lastAutoCardSyncAt: Date?
    @Published private(set) var appearanceTick: Int = 0

    var openMainWindowAction: (() -> Void)?
    var languageChangedAction: (() -> Void)?

    private let preferencesStore: PreferencesStore
    private let discovery: SessionDiscovery
    private let processMonitor: ProcessMonitor
    private let syncEngine: SessionSyncEngine
    private let rateLimitWatcher: RateLimitWatcher
    private let launchAgent: LaunchAgentManager
    private var refreshTimer: DispatchSourceTimer?
    private let watcherQueue = DispatchQueue(label: "com.berkay.ClaudeSYNC.usage-watchers", qos: .utility)
    private var fileWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var watcherDebounceWork: DispatchWorkItem?
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
        self.isShowingOnboarding = !loaded.hasCompletedOnboarding
        self.launchAtLogin = launchAgent.isEnabled

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
            // Only silently request notification permission if onboarding is already done;
            // otherwise let the user grant it intentionally in Onboarding Step 2.
            if loaded.hasCompletedOnboarding {
                NotificationHelper.shared.requestPermissionIfNeeded()
            }
            refresh()
            refreshSetupDiagnostics()
            startAutoRefresh()
        }
    }

    deinit {
        refreshTimer?.cancel()
        watcherDebounceWork?.cancel()
        for src in fileWatchers.values {
            src.cancel()
        }
        if let obs = themeObserver {
            DistributedNotificationCenter.default().removeObserver(obs)
        }
    }

    // MARK: - Computed Properties

    var isTurkish: Bool {
        settings.language.resolvedIsTurkish
    }

    var l10n: L10n {
        L10n(isTurkish: isTurkish)
    }

    var shouldShowOnboarding: Bool {
        isShowingOnboarding
    }

    func setLanguage(_ lang: AppLanguage) {
        settings.language = lang
        if !isDemoMode {
            preferencesStore.save(settings)
        }
        appearanceTick &+= 1
        languageChangedAction?()
    }

    func completeOnboarding() {
        settings.hasCompletedOnboarding = true
        isShowingOnboarding = false
        if !isDemoMode {
            preferencesStore.save(settings)
        }
    }

    func reopenOnboarding() {
        onboardingStep = .welcome
        isShowingOnboarding = true
        refreshSetupDiagnostics()
    }

    func refreshSetupDiagnostics() {
        guard !isDemoMode else { return }
        let fm = FileManager.default
        let claudeAppExists = fm.fileExists(atPath: "/Applications/Claude.app")
        let defaultDir = ProfileConfig.defaultProfile.expandedURL.path
        let dataDirReadable = fm.isReadableFile(atPath: defaultDir)
        let projectsDir = fm.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects").path
        let projectsReadable = fm.isReadableFile(atPath: projectsDir)
        let detectedCount = accounts.count

        Task { @MainActor [weak self] in
            let notifState = await NotificationHelper.shared.authorizationState()
            guard let self else { return }
            self.setupDiagnostics = SetupDiagnostics(
                claudeAppInstalled: claudeAppExists,
                claudeDataDirAccessible: dataDirReadable,
                claudeProjectsAccessible: projectsReadable,
                notificationStatus: notifState,
                detectedAccountCount: max(detectedCount, self.accounts.count)
            )
        }
    }

    func requestNotificationsFromSetup() {
        Task { @MainActor [weak self] in
            let status = await NotificationHelper.shared.requestPermissionExplicitly()
            self?.setupDiagnostics.notificationStatus = status
        }
    }

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
            isSwitching: isSwitchingNow,
            isTurkish: isTurkish
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

    // MARK: - Refresh, Live File Watchers & Background Auto-Sync Loop

    func startAutoRefresh() {
        refreshTimer?.cancel()
        let src = DispatchSource.makeTimerSource(queue: watcherQueue)
        src.schedule(deadline: .now() + .seconds(5), repeating: .seconds(5), leeway: .milliseconds(500))
        src.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.refresh(userInitiated: false)
            }
        }
        src.resume()
        refreshTimer = src
        syncUsageFileWatchers()
    }

    /// Watches exact `/usage` HTTP cache files and `plan-usage-history.json` via kernel kqueue
    /// so the Menu Bar and Dashboard react within ~300ms whenever Claude Desktop refreshes usage.
    private func syncUsageFileWatchers() {
        guard !isDemoMode else { return }
        let fm = FileManager.default
        var desiredPaths: Set<String> = []
        let orgUuids = Set(accounts.map(\.orgUuid))

        for profile in settings.allProfiles {
            let dir = profile.expandedURL.standardizedFileURL
            let histFile = dir.appendingPathComponent("plan-usage-history.json", isDirectory: false)
            if fm.fileExists(atPath: histFile.path) {
                desiredPaths.insert(histFile.path)
            }
            for org in orgUuids {
                for url in LiveUsageReader.candidateCacheFileURLs(in: dir, orgUuid: org) {
                    if fm.fileExists(atPath: url.path) {
                        desiredPaths.insert(url.path)
                    }
                }
            }
        }

        let cliState = URL(fileURLWithPath: ("~/.claude.json" as NSString).expandingTildeInPath)
        if fm.fileExists(atPath: cliState.path) {
            desiredPaths.insert(cliState.path)
        }

        // Remove stale watchers
        for (path, src) in fileWatchers where !desiredPaths.contains(path) {
            src.cancel()
            fileWatchers.removeValue(forKey: path)
        }

        // Install missing watchers
        for path in desiredPaths where fileWatchers[path] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .extend, .attrib, .rename, .delete],
                queue: watcherQueue
            )
            source.setEventHandler { [weak self] in
                guard let self else { return }
                let flags = source.data
                let needsRearm = flags.contains(.delete) || flags.contains(.rename)
                Task { @MainActor in
                    if needsRearm {
                        self.fileWatchers[path]?.cancel()
                        self.fileWatchers.removeValue(forKey: path)
                    }
                    self.scheduleDebouncedWatcherRefresh()
                }
            }
            source.setCancelHandler {
                close(fd)
            }
            source.resume()
            fileWatchers[path] = source
        }
    }

    private func scheduleDebouncedWatcherRefresh() {
        watcherDebounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.refresh(userInitiated: false)
            }
        }
        watcherDebounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(300), execute: work)
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
                    self.syncUsageFileWatchers()
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
        let srcDir = accounts.first(where: { $0.id == sourceAccountId })?.profileDataDir.standardizedFileURL
        let currentTargetValid: Bool = {
            guard let tid = targetAccountId, tid != sourceAccountId,
                  let tgt = accounts.first(where: { $0.id == tid }) else { return false }
            // Prefer a target in a DIFFERENT profile if one exists
            if let srcDir, tgt.profileDataDir.standardizedFileURL == srcDir {
                let hasCrossProfileCandidate = accounts.contains {
                    $0.id != sourceAccountId && $0.profileDataDir.standardizedFileURL != srcDir
                }
                if hasCrossProfileCandidate { return false }
            }
            return true
        }()
        if !currentTargetValid {
            if let srcDir, let cross = accounts.first(where: {
                $0.id != sourceAccountId && $0.profileDataDir.standardizedFileURL != srcDir
            }) {
                targetAccountId = cross.id
            } else {
                targetAccountId = accounts.first(where: { $0.id != sourceAccountId })?.id
            }
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
        let singleWindow = settings.singleWindowMode
        let runningPids = processSnapshot.runningInstances.map(\.pid)
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
                    if singleWindow {
                        try await mon.switchSingleWindow(
                            closingPids: runningPids,
                            targetDataDir: decision.target.profileDataDir,
                            targetIsDefault: decision.target.isDefaultProfile
                        )
                    } else if let pid = decision.target.runningPid {
                        try await mon.gracefulRestart(
                            pid: pid,
                            dataDir: decision.target.profileDataDir,
                            isDefault: decision.target.isDefaultProfile
                        )
                    } else {
                        try mon.launchProfile(
                            dataDir: decision.target.profileDataDir,
                            isDefault: decision.target.isDefaultProfile,
                            allowMultipleInstances: true
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

            let tr = self.l10n
            let title = switchedWindow
                ? tr.t(
                    "Otomatik Geçiş Tamamlandı → \(decision.target.displayName)",
                    "Auto-Failover Complete → \(decision.target.displayName)"
                )
                : tr.t(
                    "Limit Doldu · \(transferred) Oturum \(decision.target.displayName) Hesabına Aktarıldı",
                    "Rate Limit Hit · \(transferred) Session(s) Transferred to \(decision.target.displayName)"
                )
            let detail = switchedWindow
                ? tr.t(
                    "\(decision.reason). \(transferred) oturum taşındı ve \(decision.target.displayName) penceresi açıldı.",
                    "\(decision.reason). Transferred \(transferred) session(s) and switched to \(decision.target.displayName)."
                )
                : tr.t(
                    "\(decision.reason). Çıkışsız pencere geçişi için 2. profili etkinleştirebilirsiniz.",
                    "\(decision.reason). Enable Profile 2 for automatic zero-logout window switching."
                )

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
        let singleWindow = settings.singleWindowMode
        let runningPids = processSnapshot.runningInstances.map(\.pid)
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
                    if singleWindow {
                        try await mon.switchSingleWindow(
                            closingPids: runningPids,
                            targetDataDir: dst.profileDataDir,
                            targetIsDefault: dst.isDefaultProfile
                        )
                    } else if let pid = dst.runningPid {
                        try await mon.gracefulRestart(
                            pid: pid,
                            dataDir: dst.profileDataDir,
                            isDefault: dst.isDefaultProfile
                        )
                    } else {
                        try mon.launchProfile(
                            dataDir: dst.profileDataDir,
                            isDefault: dst.isDefaultProfile,
                            allowMultipleInstances: true
                        )
                    }
                    self.sourceAccountId = dst.id
                    self.targetAccountId = src.id
                    self.recomputeRelationCaches()
                    self.persistSelection()
                    let tr = self.l10n
                    self.statusBanner = StatusBanner(
                        kind: .success,
                        title: tr.t("\(dst.displayName) hesabına geçiş yapıldı", "Switched to \(dst.displayName)"),
                        detail: tr.t(
                            "\(movedIds.count) aktif oturum en üste taşındı — çıkış yapmadan devam edebilirsiniz.",
                            "\(movedIds.count) active session(s) pinned to top — continue without logging out."
                        ),
                        quickAction: nil
                    )
                } catch {
                    let tr = self.l10n
                    self.statusBanner = StatusBanner(
                        kind: .warning,
                        title: tr.t("\(movedIds.count) oturum aktarıldı, pencere açılamadı", "\(movedIds.count) session(s) synced, couldn't open window"),
                        detail: error.localizedDescription,
                        quickAction: .launchOrReloadTargetProfile(accountId: dst.id, label: tr.t("Tekrar Dene", "Retry"))
                    )
                }
            } else {
                let tr = self.l10n
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: tr.t("\(movedIds.count) oturum \(dst.displayName) hesabına aktarıldı", "\(movedIds.count) session(s) transferred to \(dst.displayName)"),
                    detail: tr.t(
                        "Çıkış/giriş yapmadan tek tıkla geçiş için Çift Profil modunu etkinleştirin.",
                        "Enable Dual Profile mode for instant zero-logout switching."
                    ),
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
        let tr = l10n
        guard let src = sourceAccount, let dst = targetAccount else {
            statusBanner = StatusBanner(
                kind: .warning,
                title: tr.t("Hedef hesap bulunamadı", "Target account not found"),
                detail: tr.t(
                    "Aktarım için en az 2 farklı hesap veya profil algılanmalıdır.",
                    "At least 2 accounts or profiles are required to transfer sessions."
                ),
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
                    let tr = self.l10n
                    self.isBusy = false
                    self.markRecentlyTransferred(session.sessionId)
                    self.refresh()

                    var detailParts: [String] = ["\(res.sourceName) → \(res.targetName)"]
                    if !res.notes.isEmpty {
                        detailParts.append(res.notes.joined(separator: " · "))
                    }
                    if session.isLiveRunning {
                        detailParts.append(
                            tr.t(
                                "Not: Bu oturum şu an açık — üretim bittikten sonra diğer hesapta devam edin.",
                                "Note: This session is currently active — wait for generation to finish before resuming in the other account."
                            )
                        )
                    }

                    let quickAction: StatusBanner.QuickAction
                    if res.wasCrossProfile {
                        let label = dst.runningPid != nil
                            ? tr.t("\(dst.displayName) Profilini Yenile", "Reload \(dst.displayName)")
                            : tr.t("\(dst.displayName) Profilini Aç", "Open \(dst.displayName)")
                        quickAction = .launchOrReloadTargetProfile(accountId: dst.id, label: label)
                    } else {
                        quickAction = .reloadDefaultClaude
                    }

                    self.statusBanner = StatusBanner(
                        kind: .success,
                        title: tr.t("\"\(res.title)\" aktarıldı", "Transferred \"\(res.title)\""),
                        detail: detailParts.joined(separator: "\n"),
                        quickAction: quickAction
                    )

                    if switchToTargetAfter && res.wasCrossProfile {
                        self.launchOrReloadProfile(forAccountId: dst.id)
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isBusy = false
                    self.statusBanner = StatusBanner(
                        kind: .error,
                        title: self.l10n.t("Aktarım başarısız", "Transfer failed"),
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
                    let tr = self.l10n
                    self.isBusy = false
                    self.refresh()

                    if !summary.errors.isEmpty {
                        self.statusBanner = StatusBanner(
                            kind: .warning,
                            title: tr.t(
                                "Eşitleme kısmen tamamlandı (\(summary.totalChanged) güncellendi)",
                                "Sync partially completed (\(summary.totalChanged) updated)"
                            ),
                            detail: summary.errors.prefix(2).joined(separator: "\n"),
                            quickAction: summary.backupDir.map { .openBackups($0) }
                        )
                    } else if summary.totalChanged == 0 {
                        self.statusBanner = StatusBanner(
                            kind: .info,
                            title: tr.t("Tüm aktif oturumlar zaten güncel", "All active sessions are already in sync"),
                            detail: tr.t(
                                "\(summary.skippedUpToDate) oturum iki hesapta da eşit durumda.",
                                "\(summary.skippedUpToDate) session(s) already up to date across both accounts."
                            ),
                            quickAction: nil
                        )
                    } else {
                        let crossProfile = src.profileDataDir.standardizedFileURL != dst.profileDataDir.standardizedFileURL
                        let action: StatusBanner.QuickAction = crossProfile
                            ? .launchOrReloadTargetProfile(
                                accountId: dst.id,
                                label: tr.t("\(dst.displayName) Profilini Yenile", "Reload \(dst.displayName)")
                            )
                            : .reloadDefaultClaude
                        self.statusBanner = StatusBanner(
                            kind: .success,
                            title: tr.t(
                                "Eşitleme tamamlandı: \(summary.copiedCount) yeni, \(summary.updatedCount) güncellendi",
                                "Sync complete: \(summary.copiedCount) copied, \(summary.updatedCount) updated"
                            ),
                            detail: tr.t(
                                "\(summary.skippedUpToDate) oturum zaten günceldi.",
                                "\(summary.skippedUpToDate) session(s) were already up to date."
                            ),
                            quickAction: action
                        )
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.isBusy = false
                    self.statusBanner = StatusBanner(
                        kind: .error,
                        title: self.l10n.t("Toplu eşitleme hatası", "Batch sync failed"),
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
        // Never pre-copy a guessed account folder before user signs into Profile 2 —
        // once signed in, Sync / Switch transfers sessions into the true logged-in account cleanly.
        setupAndLaunchSecondaryProfile(
            name: l10n.t("2. Profil", "Profile 2"),
            path: suggested.dataDirPath,
            copyMcpConfig: true,
            migrateAccount: nil
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
                    title: self.l10n.t("Claude Desktop yeniden başlatıldı", "Claude Desktop restarted"),
                    detail: self.l10n.t("Kenar çubuğu aktarılan oturumlarla yenilendi.", "Sidebar refreshed with synced sessions."),
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: self.l10n.t("Yenileme tamamlanamadı", "Restart failed"),
                    detail: error.localizedDescription,
                    quickAction: nil
                )
            }
        }
    }

    func launchOrReloadProfile(forAccountId accountId: String) {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return }
        let mon = processMonitor
        let singleWindow = settings.singleWindowMode
        let runningPids = processSnapshot.runningInstances.map(\.pid)
        isBusy = true

        Task {
            do {
                if singleWindow {
                    try await mon.switchSingleWindow(
                        closingPids: runningPids,
                        targetDataDir: account.profileDataDir,
                        targetIsDefault: account.isDefaultProfile
                    )
                } else if let pid = account.runningPid {
                    try await mon.gracefulRestart(
                        pid: pid,
                        dataDir: account.profileDataDir,
                        isDefault: account.isDefaultProfile
                    )
                } else {
                    try mon.launchProfile(
                        dataDir: account.profileDataDir,
                        isDefault: account.isDefaultProfile,
                        allowMultipleInstances: true
                    )
                }
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: self.l10n.t("\(account.displayName) açıldı", "Opened \(account.displayName)"),
                    detail: self.l10n.t("Aktarılan oturum kenar çubuğunun en üstünde hazır.", "Synced session is pinned at the top of the sidebar."),
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: self.l10n.t("Profil başlatılamadı", "Could not launch profile"),
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
            return
        }

        let displayName = l10n.profileDisplayName(profile.name, isDefault: profile.isDefault)
        if settings.singleWindowMode {
            let mon = processMonitor
            let runningPids = processSnapshot.runningInstances.map(\.pid)
            isBusy = true
            Task {
                do {
                    try await mon.switchSingleWindow(
                        closingPids: runningPids,
                        targetDataDir: dir,
                        targetIsDefault: profile.isDefault
                    )
                    self.isBusy = false
                    if let switchedAcc = self.accounts.first(where: {
                        $0.profileDataDir.standardizedFileURL.path == dir.path
                    }) {
                        let prevSource = self.sourceAccountId
                        self.sourceAccountId = switchedAcc.id
                        if prevSource != switchedAcc.id {
                            self.targetAccountId = prevSource
                        }
                        self.recomputeRelationCaches()
                        self.persistSelection()
                    }
                    self.statusBanner = StatusBanner(
                        kind: .success,
                        title: self.l10n.t("Tek pencerede \(displayName) açıldı", "Switched to \(displayName)"),
                        detail: self.l10n.t("Diğer hesap kapatıldı; bu hesapta çıkış yapmadan devam edebilirsiniz.", "Previous Claude window closed cleanly; continuing in \(displayName)."),
                        quickAction: nil
                    )
                    self.refresh()
                } catch {
                    self.isBusy = false
                    self.statusBanner = StatusBanner(
                        kind: .error,
                        title: self.l10n.t("Profil başlatılamadı", "Could not launch profile"),
                        detail: error.localizedDescription,
                        quickAction: nil
                    )
                }
            }
        } else {
            do {
                try processMonitor.launchProfile(dataDir: dir, isDefault: profile.isDefault, allowMultipleInstances: true)
                statusBanner = StatusBanner(
                    kind: .info,
                    title: l10n.t("\(displayName) başlatılıyor", "Launching \(displayName)"),
                    detail: l10n.t("Açılan pencerede hesabınız sürekli giriş yapılı kalır.", "Your account stays permanently logged in inside this window."),
                    quickAction: nil
                )
                refresh()
            } catch {
                statusBanner = StatusBanner(
                    kind: .error,
                    title: l10n.t("Profil başlatılamadı", "Could not launch profile"),
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
        let allPids = processSnapshot.runningInstances.map(\.pid)
        let singleWindow = settings.singleWindowMode
        let mon = processMonitor
        isBusy = true

        Task {
            do {
                if singleWindow {
                    try await mon.switchSingleWindow(closingPids: allPids, targetDataDir: dir, targetIsDefault: profile.isDefault)
                } else {
                    try await mon.gracefulRestart(pid: runningPid, dataDir: dir, isDefault: profile.isDefault)
                }
                self.isBusy = false
                let displayName = self.l10n.profileDisplayName(profile.name, isDefault: profile.isDefault)
                self.statusBanner = StatusBanner(
                    kind: .success,
                    title: self.l10n.t("\(displayName) yeniden başlatıldı", "Restarted \(displayName)"),
                    detail: self.l10n.t("Kenar çubuğu güncel oturumlarla yenilendi.", "Sidebar refreshed with latest sessions."),
                    quickAction: nil
                )
                self.refresh()
            } catch {
                self.isBusy = false
                self.statusBanner = StatusBanner(
                    kind: .error,
                    title: self.l10n.t("Profil yenilenemedi", "Could not restart profile"),
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
            name: trimmedName.isEmpty ? l10n.t("2. Profil", "Profile 2") : trimmedName,
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

            var extras: [String] = []
            if copiedMcp { extras.append(l10n.t("yerel MCP ayarları", "local MCP config")) }
            if let migrated = migrateAccount {
                extras.append(l10n.t("\(migrated.activeSessions.count) mevcut oturum", "\(migrated.activeSessions.count) existing sessions"))
            }
            let extraNote = extras.isEmpty
                ? ""
                : l10n.t(" (\(extras.joined(separator: " + ")) aktarıldı)", " (copied \(extras.joined(separator: " + ")))")

            if settings.singleWindowMode {
                // Close Profile 1 first so ONLY Profile 2 runs — guarantees 1 Dock icon AND Gmail/Google claude:// OAuth routes directly to Profile 2!
                let mon = processMonitor
                let runningPids = processSnapshot.runningInstances.map(\.pid)
                let targetDir = profile.expandedURL
                isBusy = true
                Task {
                    do {
                        try await mon.switchSingleWindow(
                            closingPids: runningPids,
                            targetDataDir: targetDir,
                            targetIsDefault: false
                        )
                        self.isBusy = false
                        self.statusBanner = StatusBanner(
                            kind: .success,
                            title: self.l10n.t("2. Hesap Tek Pencerede Açıldı", "Account 2 Opened in Single Window"),
                            detail: self.l10n.t(
                                "Mevcut Claude kapatıldı. Şimdi 2. hesabınızla Gmail/Google veya E-posta ile 1 kez giriş yapın; bundan sonra çıkış yapmadan tek pencerede otomatik geçiş çalışır.\(extraNote)",
                                "Primary Claude closed cleanly so Google/Gmail OAuth routes straight here. Sign in once with Account 2 — future switches run autonomously in a single window.\(extraNote)"
                            ),
                            quickAction: nil
                        )
                        self.refresh()
                    } catch {
                        self.isBusy = false
                        self.statusBanner = StatusBanner(
                            kind: .error,
                            title: self.l10n.t("2. profil başlatılamadı", "Could not launch Profile 2"),
                            detail: error.localizedDescription,
                            quickAction: nil
                        )
                    }
                }
            } else {
                try processMonitor.launchProfile(dataDir: profile.expandedURL, isDefault: false, allowMultipleInstances: true)
                statusBanner = StatusBanner(
                    kind: .success,
                    title: l10n.t("Çıkışsız 2. Profil Başlatıldı", "Isolated Profile 2 Launched"),
                    detail: l10n.t(
                        "Paralel modda 2. pencere açıldı. Gmail OAuth ana pencereye giderse E-posta ile giriş yapın veya Tek Pencere Modunu kullanın.\(extraNote)",
                        "Launched side-by-side window. Use Email sign-in if Google OAuth routes to your primary window, or enable Single Window Mode.\(extraNote)"
                    ),
                    quickAction: nil
                )
                refresh()
            }
        } catch {
            statusBanner = StatusBanner(
                kind: .error,
                title: l10n.t("2. profil oluşturulamadı", "Could not create Profile 2"),
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
            title: l10n.t("CLI devam komutu kopyalandı", "Copied CLI resume command"),
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
                title: l10n.t("Otomatik başlatma ayarlanamadı", "Could not configure Launch at Login"),
                detail: error.localizedDescription,
                quickAction: nil
            )
        }
    }

    // MARK: - Synthetic Open-Source Demo Data (strictly for --demo-snapshot screenshots)

    func loadSyntheticDemoData(isTurkish demoTurkish: Bool = false) {
        isDemoMode = true
        settings.language = demoTurkish ? .turkish : .english
        settings.hasCompletedOnboarding = true
        isShowingOnboarding = false
        setupDiagnostics = SetupDiagnostics(
            claudeAppInstalled: true,
            claudeDataDirAccessible: true,
            claudeProjectsAccessible: true,
            notificationStatus: .authorized,
            detectedAccountCount: 2
        )
        launchAtLogin = true

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
            profileName: demoTurkish ? "Ana Profil" : "Primary Profile",
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
            profileName: demoTurkish ? "2. Profil" : "Profile 2",
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
            ProfileConfig(
                id: "secondary-account-2",
                name: demoTurkish ? "2. Profil" : "Profile 2",
                dataDirPath: "~/Library/Application Support/Claude-Account2",
                isDefault: false
            )
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
