import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case system = "system"
    case turkish = "tr"
    case english = "en"

    public var id: String { rawValue }

    public var resolvedIsTurkish: Bool {
        switch self {
        case .turkish: return true
        case .english: return false
        case .system:
            return Locale.preferredLanguages.first?.lowercased().hasPrefix("tr") == true
        }
    }
}

public struct ProfileConfig: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var dataDirPath: String
    public let isDefault: Bool

    public init(id: String, name: String, dataDirPath: String, isDefault: Bool) {
        self.id = id
        self.name = name
        self.dataDirPath = dataDirPath
        self.isDefault = isDefault
    }

    public var expandedURL: URL {
        URL(fileURLWithPath: (dataDirPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func localizedName(isTurkish: Bool) -> String {
        if isDefault && (name == "Ana Profil" || name == "Primary Profile") {
            return isTurkish ? "Ana Profil" : "Primary Profile"
        }
        if id == "secondary-account-2" && (name == "2. Profil" || name == "Profile 2") {
            return isTurkish ? "2. Profil" : "Profile 2"
        }
        return name
    }

    public static var defaultProfile: ProfileConfig {
        ProfileConfig(
            id: "default",
            name: "Ana Profil",
            dataDirPath: "~/Library/Application Support/Claude",
            isDefault: true
        )
    }

    public static var suggestedSecondaryProfile: ProfileConfig {
        ProfileConfig(
            id: "secondary-account-2",
            name: "2. Profil",
            dataDirPath: "~/Library/Application Support/Claude-Account2",
            isDefault: false
        )
    }
}

public struct UsageSamplePoint: Equatable, Hashable, Identifiable, Sendable {
    public var id: Double { timestamp.timeIntervalSince1970 }
    public let timestamp: Date
    public let fiveHour: Int?
    public let sevenDay: Int?
    public let extraUsage: Int?

    public init(timestamp: Date, fiveHour: Int?, sevenDay: Int?, extraUsage: Int?) {
        self.timestamp = timestamp
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.extraUsage = extraUsage
    }
}

public struct RateLimitEvent: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { "\(cliSessionId)-\(Int(timestamp.timeIntervalSince1970))" }
    public let timestamp: Date
    public let rateLimitType: String
    public let resetsAt: Date?
    public let status: String
    public let cliSessionId: String

    public init(
        timestamp: Date,
        rateLimitType: String,
        resetsAt: Date?,
        status: String,
        cliSessionId: String
    ) {
        self.timestamp = timestamp
        self.rateLimitType = rateLimitType
        self.resetsAt = resetsAt
        self.status = status
        self.cliSessionId = cliSessionId
    }

    public var isCurrentlyRejected: Bool {
        guard status.lowercased() == "rejected" else { return false }
        let now = Date()
        if let resetsAt {
            return resetsAt > now
        }
        return now.timeIntervalSince(timestamp) < 15 * 60
    }

    public var rateLimitTypeLabel: String {
        rateLimitTypeLabel(isTurkish: true)
    }

    public func rateLimitTypeLabel(isTurkish: Bool) -> String {
        switch rateLimitType.lowercased() {
        case "five_hour": return isTurkish ? "5 Saatlik Limit" : "5-Hour Limit"
        case "seven_day": return isTurkish ? "7 Günlük Limit" : "7-Day Limit"
        default: return isTurkish ? "Kullanım Limiti" : "Usage Limit"
        }
    }

    public var eventKey: String {
        let resetSec = resetsAt.map { Int($0.timeIntervalSince1970) } ?? 0
        return "\(rateLimitType)|\(resetSec)|\(Int(timestamp.timeIntervalSince1970 / 60))"
    }
}

public struct OrgUsage: Equatable, Hashable, Sendable {
    public let orgUuid: String
    public let fiveHourPercent: Int?
    public let sevenDayPercent: Int?
    public let extraUsagePercent: Int?
    public let updatedAt: Date
    public let history: [UsageSamplePoint]
    public var lastRateLimitHit: RateLimitEvent?

    public init(
        orgUuid: String,
        fiveHourPercent: Int?,
        sevenDayPercent: Int?,
        extraUsagePercent: Int? = nil,
        updatedAt: Date,
        history: [UsageSamplePoint] = [],
        lastRateLimitHit: RateLimitEvent? = nil
    ) {
        self.orgUuid = orgUuid
        self.fiveHourPercent = fiveHourPercent
        self.sevenDayPercent = sevenDayPercent
        self.extraUsagePercent = extraUsagePercent
        self.updatedAt = updatedAt
        self.history = history
        self.lastRateLimitHit = lastRateLimitHit
    }

    public var isFresh: Bool {
        Date().timeIntervalSince(updatedAt) < 60 * 60 * 6
    }

    public var peakPercent: Int {
        max(fiveHourPercent ?? 0, sevenDayPercent ?? 0)
    }

    public var isExhausted: Bool {
        if let hit = lastRateLimitHit, hit.isCurrentlyRejected {
            return true
        }
        if let sd = sevenDayPercent, sd >= 100 { return true }
        if let fh = fiveHourPercent, fh >= 100 { return true }
        return false
    }

    public var isNearLimit: Bool {
        peakPercent >= 90 || isExhausted
    }
}

public enum AutoSwitchTrigger: String, Codable, CaseIterable, Identifiable, Sendable {
    case onRateLimitError = "onRateLimitError"
    case at95Percent = "at95Percent"
    case at100Percent = "at100Percent"

    public var id: String { rawValue }

    public var title: String {
        title(isTurkish: true)
    }

    public func title(isTurkish: Bool) -> String {
        switch self {
        case .onRateLimitError: return isTurkish ? "429 Limit Hatasında" : "On 429 Rate Limit"
        case .at95Percent: return isTurkish ? "%95 Dolunca" : "At 95% Usage"
        case .at100Percent: return isTurkish ? "%100 Dolunca" : "At 100% Usage"
        }
    }

    public var shortLabel: String {
        shortLabel(isTurkish: true)
    }

    public func shortLabel(isTurkish: Bool) -> String {
        switch self {
        case .onRateLimitError: return "429"
        case .at95Percent: return isTurkish ? "%95" : "95%"
        case .at100Percent: return isTurkish ? "%100" : "100%"
        }
    }
}

public enum MenuBarDisplayMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case iconAndBothAccounts = "iconAndBothAccounts"
    case iconAndActiveUsage = "iconAndActiveUsage"
    case iconOnly = "iconOnly"

    public var id: String { rawValue }

    public var title: String {
        title(isTurkish: true)
    }

    public func title(isTurkish: Bool) -> String {
        switch self {
        case .iconAndBothAccounts: return isTurkish ? "İki Hesap Bar" : "Dual Account Bars"
        case .iconAndActiveUsage: return isTurkish ? "Aktif 5s/7g" : "Active 5h/7d"
        case .iconOnly: return isTurkish ? "Sadece İkon" : "Icon Only"
        }
    }
}

public struct AutoCardSyncSummary: Equatable, Sendable {
    public let updatedCount: Int
    public let syncedTitles: [String]
    public let backupDir: URL?

    public init(updatedCount: Int, syncedTitles: [String], backupDir: URL?) {
        self.updatedCount = updatedCount
        self.syncedTitles = syncedTitles
        self.backupDir = backupDir
    }
}

public struct AutoSwitchDecision: Equatable, Sendable {
    public let source: AccountSlot
    public let target: AccountSlot
    public let sessionsToTransfer: [ClaudeSessionCard]
    public let reason: String
    public let eventKey: String
    public let isZeroLogoutReady: Bool

    public init(
        source: AccountSlot,
        target: AccountSlot,
        sessionsToTransfer: [ClaudeSessionCard],
        reason: String,
        eventKey: String,
        isZeroLogoutReady: Bool
    ) {
        self.source = source
        self.target = target
        self.sessionsToTransfer = sessionsToTransfer
        self.reason = reason
        self.eventKey = eventKey
        self.isZeroLogoutReady = isZeroLogoutReady
    }
}

public struct ClaudeSessionCard: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { sessionId }

    public let sessionId: String
    public let cliSessionId: String?
    public let title: String
    public let cwd: String
    public let model: String?
    public let completedTurns: Int
    public let createdAt: Date?
    public let lastActivityAt: Date?
    public let lastFocusedAt: Date?
    public let isArchived: Bool
    public let filePath: URL
    public let fileModDate: Date
    public let transcriptPath: URL?
    public let transcriptSizeBytes: Int64?
    public let isLiveRunning: Bool

    public init(
        sessionId: String,
        cliSessionId: String?,
        title: String,
        cwd: String,
        model: String?,
        completedTurns: Int,
        createdAt: Date?,
        lastActivityAt: Date?,
        lastFocusedAt: Date?,
        isArchived: Bool,
        filePath: URL,
        fileModDate: Date,
        transcriptPath: URL?,
        transcriptSizeBytes: Int64?,
        isLiveRunning: Bool
    ) {
        self.sessionId = sessionId
        self.cliSessionId = cliSessionId
        self.title = title
        self.cwd = cwd
        self.model = model
        self.completedTurns = completedTurns
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.lastFocusedAt = lastFocusedAt
        self.isArchived = isArchived
        self.filePath = filePath
        self.fileModDate = fileModDate
        self.transcriptPath = transcriptPath
        self.transcriptSizeBytes = transcriptSizeBytes
        self.isLiveRunning = isLiveRunning
    }

    public var effectiveTimestamp: Date {
        let candidates = [lastFocusedAt, lastActivityAt, createdAt, fileModDate].compactMap { $0 }
        return candidates.max() ?? fileModDate
    }

    public var activityTimestamp: Date {
        lastActivityAt ?? fileModDate
    }

    public var projectName: String {
        guard !cwd.isEmpty else { return "Bilinmeyen klasör" }
        let url = URL(fileURLWithPath: cwd)
        if isWorktree {
            let parts = url.pathComponents
            if let wtIndex = parts.firstIndex(of: ".claude"), wtIndex > 0 {
                return "\(parts[wtIndex - 1]) / \(url.lastPathComponent)"
            }
        }
        return url.lastPathComponent
    }

    public var isWorktree: Bool {
        cwd.contains("/.claude/worktrees/")
    }

    public var hasLocalTranscript: Bool {
        transcriptPath != nil
    }

    public var formattedTranscriptSize: String? {
        guard let bytes = transcriptSizeBytes else { return nil }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    public var uuidSuffix: String {
        if sessionId.hasPrefix("local_") {
            return String(sessionId.dropFirst("local_".count))
        }
        return sessionId
    }

    public var cliResumeCommand: String? {
        guard let cliId = cliSessionId, !cliId.isEmpty else { return nil }
        let escapedCwd = cwd.replacingOccurrences(of: "'", with: "'\\''")
        if cwd.isEmpty {
            return "claude --resume \(cliId)"
        }
        return "cd '\(escapedCwd)' && claude --resume \(cliId)"
    }
}

public struct AccountSlot: Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let profileId: String
    public let profileName: String
    public let profileDataDir: URL
    public let isDefaultProfile: Bool
    public let accountUuid: String
    public let orgUuid: String
    public let sessionsDir: URL
    public var displayName: String
    public var sessions: [ClaudeSessionCard]
    public var archivedIds: Set<String>
    public var usage: OrgUsage?
    public var isActiveAccount: Bool
    public var runningPid: Int32?

    public init(
        profileId: String,
        profileName: String,
        profileDataDir: URL,
        isDefaultProfile: Bool,
        accountUuid: String,
        orgUuid: String,
        sessionsDir: URL,
        displayName: String,
        sessions: [ClaudeSessionCard],
        archivedIds: Set<String>,
        usage: OrgUsage?,
        isActiveAccount: Bool,
        runningPid: Int32?
    ) {
        self.id = "\(profileId)|\(accountUuid)|\(orgUuid)"
        self.profileId = profileId
        self.profileName = profileName
        self.profileDataDir = profileDataDir
        self.isDefaultProfile = isDefaultProfile
        self.accountUuid = accountUuid
        self.orgUuid = orgUuid
        self.sessionsDir = sessionsDir
        self.displayName = displayName
        self.sessions = sessions
        self.archivedIds = archivedIds
        self.usage = usage
        self.isActiveAccount = isActiveAccount
        self.runningPid = runningPid
    }

    public var accountOrgKey: String {
        "\(accountUuid)/\(orgUuid)"
    }

    public var shortAccountTag: String {
        String(accountUuid.prefix(8))
    }

    public var activeSessions: [ClaudeSessionCard] {
        sessions.filter { !$0.isArchived && !archivedIds.contains($0.sessionId) }
    }

    public var liveSessions: [ClaudeSessionCard] {
        activeSessions.filter { $0.isLiveRunning }
    }
}

public enum SyncRelation: Equatable, Hashable, Sendable {
    case onlyInSource
    case sourceNewer(deltaTurns: Int)
    case inSync
    case targetNewer(deltaTurns: Int)

    public var needsTransferToTarget: Bool {
        switch self {
        case .onlyInSource, .sourceNewer:
            return true
        case .inSync, .targetNewer:
            return false
        }
    }
}

public struct TransferOptions: Equatable, Hashable, Sendable {
    public var clearBridgeIds: Bool
    public var clearRemoteMcp: Bool
    public var bumpLastFocusedAt: Bool
    public var unarchiveInTarget: Bool
    public var mergeWorktreeIfNeeded: Bool

    public init(
        clearBridgeIds: Bool = true,
        clearRemoteMcp: Bool = true,
        bumpLastFocusedAt: Bool = true,
        unarchiveInTarget: Bool = true,
        mergeWorktreeIfNeeded: Bool = true
    ) {
        self.clearBridgeIds = clearBridgeIds
        self.clearRemoteMcp = clearRemoteMcp
        self.bumpLastFocusedAt = bumpLastFocusedAt
        self.unarchiveInTarget = unarchiveInTarget
        self.mergeWorktreeIfNeeded = mergeWorktreeIfNeeded
    }
}

public struct TransferResult: Equatable, Sendable {
    public let sessionId: String
    public let title: String
    public let sourceName: String
    public let targetName: String
    public let destinationFile: URL
    public let backupDir: URL?
    public let notes: [String]
    public let wasCrossProfile: Bool

    public init(
        sessionId: String,
        title: String,
        sourceName: String,
        targetName: String,
        destinationFile: URL,
        backupDir: URL?,
        notes: [String],
        wasCrossProfile: Bool
    ) {
        self.sessionId = sessionId
        self.title = title
        self.sourceName = sourceName
        self.targetName = targetName
        self.destinationFile = destinationFile
        self.backupDir = backupDir
        self.notes = notes
        self.wasCrossProfile = wasCrossProfile
    }
}

public struct BatchSyncSummary: Equatable, Sendable {
    public let copiedCount: Int
    public let updatedCount: Int
    public let skippedUpToDate: Int
    public let skippedTargetNewer: Int
    public let backupDir: URL?
    public let errors: [String]

    public init(
        copiedCount: Int,
        updatedCount: Int,
        skippedUpToDate: Int,
        skippedTargetNewer: Int,
        backupDir: URL?,
        errors: [String]
    ) {
        self.copiedCount = copiedCount
        self.updatedCount = updatedCount
        self.skippedUpToDate = skippedUpToDate
        self.skippedTargetNewer = skippedTargetNewer
        self.backupDir = backupDir
        self.errors = errors
    }

    public var totalChanged: Int {
        copiedCount + updatedCount
    }
}

public struct RunningClaudeInstance: Equatable, Hashable, Sendable {
    public let pid: Int32
    public let dataDir: String
    public let isDefaultProfile: Bool

    public init(pid: Int32, dataDir: String, isDefaultProfile: Bool) {
        self.pid = pid
        self.dataDir = dataDir
        self.isDefaultProfile = isDefaultProfile
    }
}

public struct ProcessSnapshot: Equatable, Sendable {
    public let runningInstances: [RunningClaudeInstance]
    public let liveCliSessionIds: Set<String>
    public let activeAccountOrgPairs: Set<String>

    public init(
        runningInstances: [RunningClaudeInstance] = [],
        liveCliSessionIds: Set<String> = [],
        activeAccountOrgPairs: Set<String> = []
    ) {
        self.runningInstances = runningInstances
        self.liveCliSessionIds = liveCliSessionIds
        self.activeAccountOrgPairs = activeAccountOrgPairs
    }

    public static let empty = ProcessSnapshot()
}

public enum LocalizedDateFormatter {
    public static func relativeString(from date: Date, now: Date = Date(), isTurkish: Bool) -> String {
        let diff = Int(now.timeIntervalSince(date))
        if diff < 60 { return isTurkish ? "az önce" : "just now" }
        if diff < 3600 {
            let mins = diff / 60
            return isTurkish ? "\(mins) dk önce" : "\(mins)m ago"
        }
        if diff < 86400 {
            let hrs = diff / 3600
            return isTurkish ? "\(hrs) sa önce" : "\(hrs)h ago"
        }
        let days = diff / 86400
        if days < 30 {
            return isTurkish ? "\(days) gün önce" : "\(days)d ago"
        }
        let months = days / 30
        return isTurkish ? "\(months) ay önce" : "\(months)mo ago"
    }

    public static func countdownString(until futureDate: Date, now: Date = Date(), isTurkish: Bool) -> String {
        let diff = Int(futureDate.timeIntervalSince(now))
        if diff <= 0 { return isTurkish ? "yenilendi" : "reset" }
        let days = diff / 86400
        let hours = (diff % 86400) / 3600
        let minutes = (diff % 3600) / 60
        if days > 0 {
            return isTurkish ? "\(days)g \(hours)sa kaldı" : "\(days)d \(hours)h left"
        }
        if hours > 0 {
            return isTurkish ? "\(hours)sa \(minutes)dk kaldı" : "\(hours)h \(minutes)m left"
        }
        let m = max(1, minutes)
        return isTurkish ? "\(m) dk kaldı" : "\(m)m left"
    }

    public static func shortClockTime(_ date: Date, isTurkish: Bool) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: isTurkish ? "tr_TR" : "en_US")
        fmt.dateFormat = isTurkish ? "d MMM HH:mm" : "MMM d, HH:mm"
        return fmt.string(from: date)
    }
}

public enum TurkishDateFormatter {
    public static func relativeString(from date: Date, now: Date = Date()) -> String {
        LocalizedDateFormatter.relativeString(from: date, now: now, isTurkish: true)
    }

    public static func countdownString(until futureDate: Date, now: Date = Date()) -> String {
        LocalizedDateFormatter.countdownString(until: futureDate, now: now, isTurkish: true)
    }

    public static func shortClockTime(_ date: Date) -> String {
        LocalizedDateFormatter.shortClockTime(date, isTurkish: true)
    }
}
