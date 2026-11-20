import Foundation

public struct BridgeSettings: Codable, Equatable, Sendable {
    public var accountNicknames: [String: String]
    public var secondaryProfiles: [ProfileConfig]
    public var clearBridgeIds: Bool
    public var clearRemoteMcp: Bool
    public var bumpLastFocusedAt: Bool
    public var mergeWorktreeIfNeeded: Bool
    public var showArchivedSessions: Bool
    public var selectedSourceAccountId: String?
    public var selectedTargetAccountId: String?
    public var autoSwitchEnabled: Bool
    public var autoSwitchTrigger: AutoSwitchTrigger
    public var autoSwitchTransferAllLive: Bool
    public var autoSwitchNotify: Bool
    public var autoSyncSharedCards: Bool
    public var showMenuBarExtra: Bool
    public var keepRunningInMenuBarOnClose: Bool
    public var menuBarDisplayMode: MenuBarDisplayMode
    public var lastAutoSwitchEventKey: String?
    public var language: AppLanguage
    public var hasCompletedOnboarding: Bool
    public var singleWindowMode: Bool

    public init(
        accountNicknames: [String: String] = [:],
        secondaryProfiles: [ProfileConfig] = [],
        clearBridgeIds: Bool = true,
        clearRemoteMcp: Bool = true,
        bumpLastFocusedAt: Bool = true,
        mergeWorktreeIfNeeded: Bool = true,
        showArchivedSessions: Bool = false,
        selectedSourceAccountId: String? = nil,
        selectedTargetAccountId: String? = nil,
        autoSwitchEnabled: Bool = true,
        autoSwitchTrigger: AutoSwitchTrigger = .onRateLimitError,
        autoSwitchTransferAllLive: Bool = true,
        autoSwitchNotify: Bool = true,
        autoSyncSharedCards: Bool = true,
        showMenuBarExtra: Bool = true,
        keepRunningInMenuBarOnClose: Bool = true,
        menuBarDisplayMode: MenuBarDisplayMode = .iconAndBothAccounts,
        lastAutoSwitchEventKey: String? = nil,
        language: AppLanguage = .system,
        hasCompletedOnboarding: Bool = false,
        singleWindowMode: Bool = true
    ) {
        self.accountNicknames = accountNicknames
        self.secondaryProfiles = secondaryProfiles
        self.clearBridgeIds = clearBridgeIds
        self.clearRemoteMcp = clearRemoteMcp
        self.bumpLastFocusedAt = bumpLastFocusedAt
        self.mergeWorktreeIfNeeded = mergeWorktreeIfNeeded
        self.showArchivedSessions = showArchivedSessions
        self.selectedSourceAccountId = selectedSourceAccountId
        self.selectedTargetAccountId = selectedTargetAccountId
        self.autoSwitchEnabled = autoSwitchEnabled
        self.autoSwitchTrigger = autoSwitchTrigger
        self.autoSwitchTransferAllLive = autoSwitchTransferAllLive
        self.autoSwitchNotify = autoSwitchNotify
        self.autoSyncSharedCards = autoSyncSharedCards
        self.showMenuBarExtra = showMenuBarExtra
        self.keepRunningInMenuBarOnClose = keepRunningInMenuBarOnClose
        self.menuBarDisplayMode = menuBarDisplayMode
        self.lastAutoSwitchEventKey = lastAutoSwitchEventKey
        self.language = language
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.singleWindowMode = singleWindowMode
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accountNicknames = try c.decodeIfPresent([String: String].self, forKey: .accountNicknames) ?? [:]
        secondaryProfiles = try c.decodeIfPresent([ProfileConfig].self, forKey: .secondaryProfiles) ?? []
        clearBridgeIds = try c.decodeIfPresent(Bool.self, forKey: .clearBridgeIds) ?? true
        clearRemoteMcp = try c.decodeIfPresent(Bool.self, forKey: .clearRemoteMcp) ?? true
        bumpLastFocusedAt = try c.decodeIfPresent(Bool.self, forKey: .bumpLastFocusedAt) ?? true
        mergeWorktreeIfNeeded = try c.decodeIfPresent(Bool.self, forKey: .mergeWorktreeIfNeeded) ?? true
        showArchivedSessions = try c.decodeIfPresent(Bool.self, forKey: .showArchivedSessions) ?? false
        selectedSourceAccountId = try c.decodeIfPresent(String.self, forKey: .selectedSourceAccountId)
        selectedTargetAccountId = try c.decodeIfPresent(String.self, forKey: .selectedTargetAccountId)
        autoSwitchEnabled = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchEnabled) ?? true
        autoSwitchTrigger = try c.decodeIfPresent(AutoSwitchTrigger.self, forKey: .autoSwitchTrigger) ?? .onRateLimitError
        autoSwitchTransferAllLive = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchTransferAllLive) ?? true
        autoSwitchNotify = try c.decodeIfPresent(Bool.self, forKey: .autoSwitchNotify) ?? true
        autoSyncSharedCards = try c.decodeIfPresent(Bool.self, forKey: .autoSyncSharedCards) ?? true
        showMenuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .showMenuBarExtra) ?? true
        keepRunningInMenuBarOnClose = try c.decodeIfPresent(Bool.self, forKey: .keepRunningInMenuBarOnClose) ?? true
        menuBarDisplayMode = try c.decodeIfPresent(MenuBarDisplayMode.self, forKey: .menuBarDisplayMode) ?? .iconAndBothAccounts
        lastAutoSwitchEventKey = try c.decodeIfPresent(String.self, forKey: .lastAutoSwitchEventKey)
        language = try c.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        singleWindowMode = try c.decodeIfPresent(Bool.self, forKey: .singleWindowMode) ?? true
    }

    public var transferOptions: TransferOptions {
        TransferOptions(
            clearBridgeIds: clearBridgeIds,
            clearRemoteMcp: clearRemoteMcp,
            bumpLastFocusedAt: bumpLastFocusedAt,
            unarchiveInTarget: true,
            mergeWorktreeIfNeeded: mergeWorktreeIfNeeded
        )
    }

    public var allProfiles: [ProfileConfig] {
        var list = [ProfileConfig.defaultProfile]
        var seen = Set([ProfileConfig.defaultProfile.expandedURL.standardizedFileURL.path])
        for p in secondaryProfiles {
            let std = p.expandedURL.standardizedFileURL.path
            if !seen.contains(std) {
                seen.insert(std)
                list.append(p)
            }
        }
        return list
    }
}

public final class PreferencesStore: @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "com.claudesync.settings.v1"
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> BridgeSettings {
        lock.lock()
        defer { lock.unlock() }
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(BridgeSettings.self, from: data) {
            return decoded
        }
        var initial = BridgeSettings()
        let suggested = ProfileConfig.suggestedSecondaryProfile
        if FileManager.default.fileExists(atPath: suggested.expandedURL.path) {
            initial.secondaryProfiles = [suggested]
        }
        return initial
    }

    public func save(_ settings: BridgeSettings) {
        lock.lock()
        defer { lock.unlock() }
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
