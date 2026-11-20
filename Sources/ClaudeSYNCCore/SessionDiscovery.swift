import Foundation

public final class SessionDiscovery: @unchecked Sendable {
    public let claudeProjectsDir: URL
    public let rateLimitWatcher: RateLimitWatcher
    public let liveUsageReader: LiveUsageReader

    private struct CachedCard {
        let modDate: Date
        let size: Int64
        let raw: RawSessionCard
    }

    private struct CachedRateLimit {
        let modDate: Date
        let size: Int64
        let event: RateLimitEvent?
    }

    private let cacheLock = NSLock()
    private var cardCache: [String: CachedCard] = [:]
    private var rateLimitCache: [String: CachedRateLimit] = [:]
    private var liveHistoryByOrg: [String: [UsageSamplePoint]] = [:]

    public init(
        claudeProjectsDir: URL = SessionDiscovery.defaultClaudeProjectsDir,
        rateLimitWatcher: RateLimitWatcher = RateLimitWatcher(),
        liveUsageReader: LiveUsageReader = LiveUsageReader()
    ) {
        self.claudeProjectsDir = claudeProjectsDir
        self.rateLimitWatcher = rateLimitWatcher
        self.liveUsageReader = liveUsageReader
    }

    public static var defaultClaudeProjectsDir: URL {
        URL(fileURLWithPath: ("~/.claude/projects" as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func discoverAccounts(
        profiles: [ProfileConfig],
        nicknames: [String: String],
        processSnapshot: ProcessSnapshot,
        now: Date = Date()
    ) -> [AccountSlot] {
        let fm = FileManager.default
        let transcriptIndex = buildTranscriptIndex(fm: fm)

        // 1. Collect all known org UUIDs from both plan-usage-history.json AND claude-code-sessions dirs
        var perProfileUsageByPath: [String: [String: OrgUsage]] = [:]
        var mergedUsageByOrg: [String: OrgUsage] = [:]
        var allOrgUuids: Set<String> = []

        for profile in profiles {
            let profileDir = profile.expandedURL.standardizedFileURL
            let stdPath = profileDir.path
            let perProfile = readUsageHistory(in: profileDir)
            perProfileUsageByPath[stdPath] = perProfile
            allOrgUuids.formUnion(perProfile.keys)

            let sessionsRoot = profileDir.appendingPathComponent("claude-code-sessions", isDirectory: true)
            for accDir in subdirectories(at: sessionsRoot, fm: fm) where isLikelyUUID(accDir.lastPathComponent) {
                for orgDir in subdirectories(at: accDir, fm: fm) where isLikelyUUID(orgDir.lastPathComponent) {
                    allOrgUuids.insert(orgDir.lastPathComponent)
                }
            }
        }

        // 2. Enrich per-profile usage with O(1) live Chromium Simple Cache `/usage` responses
        //    (Claude Desktop pauses plan-usage-history.json after 15m, while Cache_Data stays live!)
        for profile in profiles {
            let profileDir = profile.expandedURL.standardizedFileURL
            let stdPath = profileDir.path
            var perProfile = perProfileUsageByPath[stdPath] ?? [:]

            for orgUuid in allOrgUuids {
                if let live = liveUsageReader.readFreshestCacheUsage(in: profileDir, orgUuid: orgUuid) {
                    recordLiveObservation(orgUuid: orgUuid, reading: live)
                    let livePoint = UsageSamplePoint(
                        timestamp: live.updatedAt,
                        fiveHour: live.fiveHourPercent,
                        sevenDay: live.sevenDayPercent,
                        extraUsage: live.extraUsagePercent
                    )
                    if let existing = perProfile[orgUuid] {
                        perProfile[orgUuid] = mergeOrgUsage(existing, withLive: live, point: livePoint)
                    } else {
                        perProfile[orgUuid] = OrgUsage(
                            orgUuid: orgUuid,
                            fiveHourPercent: live.fiveHourPercent,
                            sevenDayPercent: live.sevenDayPercent,
                            extraUsagePercent: live.extraUsagePercent,
                            fiveHourResetsAt: live.fiveHourResetsAt,
                            sevenDayResetsAt: live.sevenDayResetsAt,
                            updatedAt: live.updatedAt,
                            history: [livePoint],
                            lastRateLimitHit: nil,
                            source: .liveCache
                        )
                    }
                }
            }
            perProfileUsageByPath[stdPath] = perProfile

            for (org, usage) in perProfile {
                if let existing = mergedUsageByOrg[org] {
                    mergedUsageByOrg[org] = mergeOrgUsages(existing, usage)
                } else {
                    mergedUsageByOrg[org] = usage
                }
            }
        }

        // Merge any recorded live session observations into sparkline timelines
        cacheLock.lock()
        let liveHistSnapshot = liveHistoryByOrg
        cacheLock.unlock()
        for (org, points) in liveHistSnapshot {
            if let existing = mergedUsageByOrg[org] {
                mergedUsageByOrg[org] = OrgUsage(
                    orgUuid: existing.orgUuid,
                    fiveHourPercent: existing.fiveHourPercent,
                    sevenDayPercent: existing.sevenDayPercent,
                    extraUsagePercent: existing.extraUsagePercent,
                    fiveHourResetsAt: existing.fiveHourResetsAt,
                    sevenDayResetsAt: existing.sevenDayResetsAt,
                    updatedAt: existing.updatedAt,
                    history: mergeHistory(existing.history, points),
                    lastRateLimitHit: existing.lastRateLimitHit,
                    source: existing.source
                )
            }
        }

        let cliUsage = liveUsageReader.readClaudeCLIUsage()

        var result: [AccountSlot] = []
        var defaultCounter = 0

        for profile in profiles {
            let profileDir = profile.expandedURL.standardizedFileURL
            let sessionsRoot = profileDir.appendingPathComponent("claude-code-sessions", isDirectory: true)
            guard fm.fileExists(atPath: sessionsRoot.path) else { continue }

            let runningInstance = processSnapshot.runningInstances.first {
                $0.dataDir == profileDir.path || (profile.isDefault && $0.isDefaultProfile)
            }

            // Local non-secret ownership signals written directly by Claude Desktop inside THIS profile
            let localAgentRoot = profileDir.appendingPathComponent("local-agent-mode-sessions", isDirectory: true)
            let localAgentAccountUuids = Set(
                subdirectories(at: localAgentRoot, fm: fm)
                    .map { $0.lastPathComponent.lowercased() }
                    .filter { isLikelyUUID($0) }
            )
            let ownProfileUsage = perProfileUsageByPath[profileDir.path] ?? [:]

            let accountDirs = subdirectories(at: sessionsRoot, fm: fm)
                .filter { isLikelyUUID($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var profileSlots: [AccountSlot] = []

            for accDir in accountDirs {
                let accUuid = accDir.lastPathComponent
                let orgDirs = subdirectories(at: accDir, fm: fm)
                    .filter { isLikelyUUID($0.lastPathComponent) }

                guard !orgDirs.isEmpty else { continue }

                var orgsWithSessions: [(url: URL, files: [URL])] = []
                for orgDir in orgDirs {
                    let localFiles = localSessionFiles(in: orgDir, fm: fm)
                    if !localFiles.isEmpty {
                        orgsWithSessions.append((orgDir, localFiles))
                    }
                }

                let selectedOrgs: [(url: URL, files: [URL])]
                if !orgsWithSessions.isEmpty {
                    selectedOrgs = orgsWithSessions.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
                } else {
                    let newest = orgDirs.max { a, b in
                        modDate(of: a, fm: fm) < modDate(of: b, fm: fm)
                    }
                    selectedOrgs = newest.map { [($0, [])] } ?? []
                }

                for (orgDir, localFiles) in selectedOrgs {
                    let orgUuid = orgDir.lastPathComponent
                    let archivedIds = readArchivedIds(in: orgDir)

                    var cards: [ClaudeSessionCard] = []
                    cards.reserveCapacity(localFiles.count)
                    for fileURL in localFiles {
                        if let card = parseSessionCardCached(
                            fileURL: fileURL,
                            archivedIds: archivedIds,
                            transcriptIndex: transcriptIndex,
                            liveCliIds: processSnapshot.liveCliSessionIds,
                            fm: fm
                        ) {
                            cards.append(card)
                        }
                    }

                    cards.sort { a, b in
                        if a.isLiveRunning != b.isLiveRunning {
                            return a.isLiveRunning && !b.isLiveRunning
                        }
                        return a.effectiveTimestamp > b.effectiveTimestamp
                    }

                    defaultCounter += 1
                    let key = "\(accUuid)/\(orgUuid)"
                    let customName = nicknames[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let displayName: String
                    if let customName, !customName.isEmpty {
                        displayName = customName
                    } else if !profile.isDefault {
                        displayName = "\(profile.name) (\(String(accUuid.prefix(6))))"
                    } else {
                        displayName = "Hesap \(defaultCounter) (\(String(accUuid.prefix(6))))"
                    }

                    let pairLower = key.lowercased()
                    let activeFromAgent = processSnapshot.activeAccountOrgPairs.contains(pairLower)

                    // Cached tail scan for rate-limit events + safe last-resort CLI fallback
                    let rateLimitHit = scanLatestRateLimitCached(for: cards, fm: fm)
                    var usage = mergedUsageByOrg[orgUuid]

                    // ~/.claude.json is a single global file shared across accounts (Claude Desktop spawns embedded
                    // `claude` under the active Desktop account, which can write Account A's numbers under Account B's
                    // stale `oauthAccount.accountUuid`). Therefore NEVER overwrite org-scoped Cache_Data / plan-usage-history
                    // with ~/.claude.json — only use it as a fallback when no org-scoped usage exists at all.
                    if usage == nil, let cli = cliUsage, cli.accountUuid == accUuid.lowercased() {
                        let cliPoint = UsageSamplePoint(
                            timestamp: cli.updatedAt,
                            fiveHour: cli.fiveHourPercent,
                            sevenDay: cli.sevenDayPercent,
                            extraUsage: cli.extraUsagePercent
                        )
                        usage = OrgUsage(
                            orgUuid: orgUuid,
                            fiveHourPercent: cli.fiveHourPercent,
                            sevenDayPercent: cli.sevenDayPercent,
                            extraUsagePercent: cli.extraUsagePercent,
                            fiveHourResetsAt: cli.fiveHourResetsAt,
                            sevenDayResetsAt: cli.sevenDayResetsAt,
                            updatedAt: cli.updatedAt,
                            history: [cliPoint],
                            lastRateLimitHit: nil,
                            source: .claudeCLI
                        )
                    }

                    if let hit = rateLimitHit {
                        if let existingUsage = usage {
                            let hitIsNewerAndActive = hit.isCurrentlyRejected && hit.timestamp >= existingUsage.updatedAt
                            let isFiveHourHit = hit.rateLimitType.lowercased() == "five_hour"
                            let isSevenDayHit = hit.rateLimitType.lowercased() == "seven_day"
                            usage = OrgUsage(
                                orgUuid: existingUsage.orgUuid,
                                fiveHourPercent: (hitIsNewerAndActive && isFiveHourHit) ? 100 : existingUsage.fiveHourPercent,
                                sevenDayPercent: (hitIsNewerAndActive && isSevenDayHit) ? 100 : existingUsage.sevenDayPercent,
                                extraUsagePercent: existingUsage.extraUsagePercent,
                                fiveHourResetsAt: (hitIsNewerAndActive && isFiveHourHit) ? (hit.resetsAt ?? existingUsage.fiveHourResetsAt) : existingUsage.fiveHourResetsAt,
                                sevenDayResetsAt: (hitIsNewerAndActive && isSevenDayHit) ? (hit.resetsAt ?? existingUsage.sevenDayResetsAt) : existingUsage.sevenDayResetsAt,
                                updatedAt: hitIsNewerAndActive ? hit.timestamp : existingUsage.updatedAt,
                                history: existingUsage.history,
                                lastRateLimitHit: hit,
                                source: hitIsNewerAndActive ? .rateLimitLog : existingUsage.source
                            )
                        } else {
                            let isFiveHourHit = hit.rateLimitType.lowercased() == "five_hour"
                            let isSevenDayHit = hit.rateLimitType.lowercased() == "seven_day"
                            usage = OrgUsage(
                                orgUuid: orgUuid,
                                fiveHourPercent: isFiveHourHit ? 100 : nil,
                                sevenDayPercent: isSevenDayHit ? 100 : nil,
                                extraUsagePercent: nil,
                                fiveHourResetsAt: isFiveHourHit ? hit.resetsAt : nil,
                                sevenDayResetsAt: isSevenDayHit ? hit.resetsAt : nil,
                                updatedAt: hit.timestamp,
                                history: [],
                                lastRateLimitHit: hit,
                                source: .rateLimitLog
                            )
                        }
                    }

                    if let currentUsage = usage {
                        usage = applyWindowRollover(currentUsage, now: now)
                    }

                    let slot = AccountSlot(
                        profileId: profile.id,
                        profileName: profile.name,
                        profileDataDir: profileDir,
                        isDefaultProfile: profile.isDefault,
                        accountUuid: accUuid,
                        orgUuid: orgUuid,
                        sessionsDir: orgDir,
                        displayName: displayName,
                        sessions: cards,
                        archivedIds: archivedIds,
                        usage: usage,
                        isActiveAccount: activeFromAgent,
                        runningPid: runningInstance?.pid
                    )
                    profileSlots.append(slot)
                }
            }

            // For an isolated secondary profile (!isDefault), keep ONLY the real logged-in owner account
            // if stray pre-copied/migrated folders exist alongside it.
            if !profile.isDefault && profileSlots.count > 1 {
                let bestOwner = profileSlots.max { lhs, rhs in
                    func ownerScore(_ slot: AccountSlot) -> (Int, TimeInterval, TimeInterval) {
                        var score = 0
                        if processSnapshot.activeAccountOrgPairs.contains(slot.accountOrgKey.lowercased()) {
                            score += 4000
                        }
                        if localAgentAccountUuids.contains(slot.accountUuid.lowercased()) {
                            score += 2000
                        }
                        let ownUsageDate = ownProfileUsage[slot.orgUuid]?.updatedAt.timeIntervalSince1970 ?? 0
                        if ownUsageDate > 0 {
                            score += 1000
                        }
                        let latestCard = slot.sessions.first?.effectiveTimestamp.timeIntervalSince1970 ?? 0
                        return (score, ownUsageDate, latestCard)
                    }
                    return ownerScore(lhs) < ownerScore(rhs)
                }
                if let bestOwner {
                    profileSlots = [bestOwner]
                }
            }

            // Within a single profile, mark active account accurately:
            // If any Claude Desktop instance is running on the system, ONLY running profile(s) can be active.
            let anyInstanceRunning = !processSnapshot.runningInstances.isEmpty
            if !profileSlots.isEmpty {
                if anyInstanceRunning && runningInstance == nil {
                    for i in profileSlots.indices {
                        profileSlots[i].isActiveAccount = false
                    }
                } else {
                    let agentActiveIndices = profileSlots.indices.filter { profileSlots[$0].isActiveAccount }
                    let chosenIdx: Int
                    if agentActiveIndices.count == 1 {
                        chosenIdx = agentActiveIndices[0]
                    } else {
                        let pool = agentActiveIndices.isEmpty ? Array(profileSlots.indices) : agentActiveIndices
                        chosenIdx = pool.max(by: { lhs, rhs in
                            let lOwnDate = ownProfileUsage[profileSlots[lhs].orgUuid]?.updatedAt
                                ?? profileSlots[lhs].usage?.updatedAt
                                ?? .distantPast
                            let rOwnDate = ownProfileUsage[profileSlots[rhs].orgUuid]?.updatedAt
                                ?? profileSlots[rhs].usage?.updatedAt
                                ?? .distantPast
                            if abs(lOwnDate.timeIntervalSince(rOwnDate)) > 5 {
                                return lOwnDate < rOwnDate
                            }
                            let lSessDate = profileSlots[lhs].sessions.first?.effectiveTimestamp ?? .distantPast
                            let rSessDate = profileSlots[rhs].sessions.first?.effectiveTimestamp ?? .distantPast
                            return lSessDate < rSessDate
                        }) ?? 0
                    }
                    for i in profileSlots.indices {
                        profileSlots[i].isActiveAccount = (i == chosenIdx)
                    }
                }
            }

            result.append(contentsOf: profileSlots)
        }

        // Deduplicate: if an accountOrgKey has a dedicated secondary profile, hide stale copy from default profile
        // ONLY when default profile still retains at least one other account (never wipe out default profile completely!).
        let dedicatedSecondaryKeys = Set(result.filter { !$0.isDefaultProfile }.map(\.accountOrgKey))
        if !dedicatedSecondaryKeys.isEmpty {
            let defaultSlots = result.filter(\.isDefaultProfile)
            let survivingDefaultSlots = defaultSlots.filter {
                !dedicatedSecondaryKeys.contains($0.accountOrgKey) || $0.isActiveAccount
            }
            if !survivingDefaultSlots.isEmpty {
                result = result.filter { slot in
                    if slot.isDefaultProfile && dedicatedSecondaryKeys.contains(slot.accountOrgKey) && !slot.isActiveAccount {
                        return false
                    }
                    return true
                }
            }
        }

        result.sort { a, b in
            if a.isActiveAccount != b.isActiveAccount { return a.isActiveAccount && !b.isActiveAccount }
            if a.isDefaultProfile != b.isDefaultProfile { return a.isDefaultProfile && !b.isDefaultProfile }
            let aDate = a.sessions.first?.effectiveTimestamp ?? .distantPast
            let bDate = b.sessions.first?.effectiveTimestamp ?? .distantPast
            if aDate != bDate { return aDate > bDate }
            return a.id < b.id
        }

        return result
    }

    // MARK: - Private Cached Parsers

    private func scanLatestRateLimitCached(for sessions: [ClaudeSessionCard], fm: FileManager) -> RateLimitEvent? {
        let candidates = sessions.filter { $0.transcriptPath != nil }.prefix(8)
        var latest: RateLimitEvent?

        for session in candidates {
            guard let path = session.transcriptPath, let cliId = session.cliSessionId else { continue }
            let vals = try? path.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let mdate = vals?.contentModificationDate ?? .distantPast
            let size = Int64(vals?.fileSize ?? 0)
            let key = path.path

            let event: RateLimitEvent?
            cacheLock.lock()
            let cached = rateLimitCache[key]
            cacheLock.unlock()

            if let cached, cached.modDate == mdate, cached.size == size {
                event = cached.event
            } else {
                let parsed = rateLimitWatcher.parseTailForRateLimit(fileURL: path, cliSessionId: cliId)
                cacheLock.lock()
                rateLimitCache[key] = CachedRateLimit(modDate: mdate, size: size, event: parsed)
                cacheLock.unlock()
                event = parsed
            }

            if let ev = event {
                if let existing = latest {
                    if ev.timestamp > existing.timestamp { latest = ev }
                } else {
                    latest = ev
                }
            }
        }
        return latest
    }

    private func mergeHistory(_ a: [UsageSamplePoint], _ b: [UsageSamplePoint]) -> [UsageSamplePoint] {
        var bySec: [Int: UsageSamplePoint] = [:]
        for p in a + b {
            bySec[Int(p.timestamp.timeIntervalSince1970)] = p
        }
        return bySec.values.sorted { $0.timestamp < $1.timestamp }.suffix(60)
    }

    private func recordLiveObservation(orgUuid: String, reading: LiveUsageReading) {
        let point = UsageSamplePoint(
            timestamp: reading.updatedAt,
            fiveHour: reading.fiveHourPercent,
            sevenDay: reading.sevenDayPercent,
            extraUsage: reading.extraUsagePercent
        )
        cacheLock.lock()
        var arr = liveHistoryByOrg[orgUuid] ?? []
        let sec = Int(point.timestamp.timeIntervalSince1970)
        if !arr.contains(where: { Int($0.timestamp.timeIntervalSince1970) == sec }) {
            arr.append(point)
            arr.sort { $0.timestamp < $1.timestamp }
            if arr.count > 60 { arr.removeFirst(arr.count - 60) }
            liveHistoryByOrg[orgUuid] = arr
        }
        cacheLock.unlock()
    }

    private func mergeOrgUsage(
        _ existing: OrgUsage,
        withLive live: LiveUsageReading,
        point: UsageSamplePoint
    ) -> OrgUsage {
        let combinedHistory = mergeHistory(existing.history, [point])
        // Prefer live reading when strictly newer, OR within 2s of plan-usage-history (since live carries resets_at)
        let liveWins = live.updatedAt.timeIntervalSince(existing.updatedAt) >= -2.0
        if liveWins {
            return OrgUsage(
                orgUuid: existing.orgUuid,
                fiveHourPercent: live.fiveHourPercent,
                sevenDayPercent: live.sevenDayPercent ?? existing.sevenDayPercent,
                extraUsagePercent: live.extraUsagePercent ?? existing.extraUsagePercent,
                fiveHourResetsAt: live.fiveHourResetsAt ?? existing.fiveHourResetsAt,
                sevenDayResetsAt: live.sevenDayResetsAt ?? existing.sevenDayResetsAt,
                updatedAt: max(live.updatedAt, existing.updatedAt),
                history: combinedHistory,
                lastRateLimitHit: existing.lastRateLimitHit,
                source: live.source
            )
        } else {
            return OrgUsage(
                orgUuid: existing.orgUuid,
                fiveHourPercent: existing.fiveHourPercent,
                sevenDayPercent: existing.sevenDayPercent,
                extraUsagePercent: existing.extraUsagePercent ?? live.extraUsagePercent,
                fiveHourResetsAt: existing.fiveHourResetsAt ?? live.fiveHourResetsAt,
                sevenDayResetsAt: existing.sevenDayResetsAt ?? live.sevenDayResetsAt,
                updatedAt: existing.updatedAt,
                history: combinedHistory,
                lastRateLimitHit: existing.lastRateLimitHit,
                source: existing.source
            )
        }
    }

    private func mergeOrgUsages(_ a: OrgUsage, _ b: OrgUsage) -> OrgUsage {
        let combinedHistory = mergeHistory(a.history, b.history)
        let bWins: Bool
        if abs(b.updatedAt.timeIntervalSince(a.updatedAt)) <= 2.0 {
            bWins = (b.source == .liveCache && a.source != .liveCache)
                || (b.fiveHourResetsAt != nil && a.fiveHourResetsAt == nil)
        } else {
            bWins = b.updatedAt > a.updatedAt
        }
        let newer = bWins ? b : a
        let older = bWins ? a : b
        return OrgUsage(
            orgUuid: newer.orgUuid,
            fiveHourPercent: newer.fiveHourPercent,
            sevenDayPercent: newer.sevenDayPercent ?? older.sevenDayPercent,
            extraUsagePercent: newer.extraUsagePercent ?? older.extraUsagePercent,
            fiveHourResetsAt: newer.fiveHourResetsAt ?? older.fiveHourResetsAt,
            sevenDayResetsAt: newer.sevenDayResetsAt ?? older.sevenDayResetsAt,
            updatedAt: newer.updatedAt,
            history: combinedHistory,
            lastRateLimitHit: newer.lastRateLimitHit ?? older.lastRateLimitHit,
            source: newer.source
        )
    }

    /// Automatically resets expired 5-hour or 7-day windows once their exact server `resets_at` boundary passes.
    private func applyWindowRollover(_ usage: OrgUsage, now: Date) -> OrgUsage {
        var fh = usage.fiveHourPercent
        var fhReset = usage.fiveHourResetsAt
        if let reset = fhReset, usage.updatedAt < reset, now >= reset {
            fh = 0
            fhReset = nil
        }

        var sd = usage.sevenDayPercent
        var sdReset = usage.sevenDayResetsAt
        if let reset = sdReset, usage.updatedAt < reset, now >= reset {
            sd = 0
            sdReset = nil
        }

        if fh == usage.fiveHourPercent && sd == usage.sevenDayPercent
            && fhReset == usage.fiveHourResetsAt && sdReset == usage.sevenDayResetsAt {
            return usage
        }

        return OrgUsage(
            orgUuid: usage.orgUuid,
            fiveHourPercent: fh,
            sevenDayPercent: sd,
            extraUsagePercent: usage.extraUsagePercent,
            fiveHourResetsAt: fhReset,
            sevenDayResetsAt: sdReset,
            updatedAt: usage.updatedAt,
            history: usage.history,
            lastRateLimitHit: usage.lastRateLimitHit,
            source: usage.source
        )
    }

    private struct TranscriptEntry {
        let url: URL
        let size: Int64
    }

    private func buildTranscriptIndex(fm: FileManager) -> [String: TranscriptEntry] {
        var index: [String: TranscriptEntry] = [:]
        guard fm.fileExists(atPath: claudeProjectsDir.path) else { return index }

        let projectDirs = subdirectories(at: claudeProjectsDir, fm: fm)
        for projectDir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                let id = file.deletingPathExtension().lastPathComponent.lowercased()
                let vals = try? file.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(vals?.fileSize ?? 0)
                if let existing = index[id], existing.size >= size {
                    continue
                }
                index[id] = TranscriptEntry(url: file, size: size)
            }
        }
        return index
    }

    private struct RawSessionCard: Decodable {
        let sessionId: String?
        let cliSessionId: String?
        let title: String?
        let cwd: String?
        let model: String?
        let completedTurns: Int?
        let createdAt: Double?
        let lastActivityAt: Double?
        let lastFocusedAt: Double?
        let isArchived: Bool?
    }

    private func parseSessionCardCached(
        fileURL: URL,
        archivedIds: Set<String>,
        transcriptIndex: [String: TranscriptEntry],
        liveCliIds: Set<String>,
        fm: FileManager
    ) -> ClaudeSessionCard? {
        let vals = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mdate = vals?.contentModificationDate ?? .distantPast
        let fsize = Int64(vals?.fileSize ?? 0)
        let key = fileURL.path

        let raw: RawSessionCard
        cacheLock.lock()
        let cached = cardCache[key]
        cacheLock.unlock()

        if let cached, cached.modDate == mdate, cached.size == fsize {
            raw = cached.raw
        } else {
            guard let data = try? Data(contentsOf: fileURL),
                  let decoded = try? JSONDecoder().decode(RawSessionCard.self, from: data) else {
                return nil
            }
            cacheLock.lock()
            cardCache[key] = CachedCard(modDate: mdate, size: fsize, raw: decoded)
            cacheLock.unlock()
            raw = decoded
        }

        let fallbackSessionId = fileURL.deletingPathExtension().lastPathComponent
        let sessionId = raw.sessionId ?? fallbackSessionId
        let cliId = raw.cliSessionId
        let cliLower = cliId?.lowercased()
        let transcript = cliLower.flatMap { transcriptIndex[$0] }
        let isLive = cliLower.map { liveCliIds.contains($0) } ?? false

        let title = (raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap {
            $0.isEmpty ? nil : $0
        } ?? "Başlıksız Oturum (\(String(sessionId.suffix(6))))"

        return ClaudeSessionCard(
            sessionId: sessionId,
            cliSessionId: cliId,
            title: title,
            cwd: raw.cwd ?? "",
            model: raw.model,
            completedTurns: raw.completedTurns ?? 0,
            createdAt: raw.createdAt.map { Date(timeIntervalSince1970: $0 / 1000.0) },
            lastActivityAt: raw.lastActivityAt.map { Date(timeIntervalSince1970: $0 / 1000.0) },
            lastFocusedAt: raw.lastFocusedAt.map { Date(timeIntervalSince1970: $0 / 1000.0) },
            isArchived: (raw.isArchived ?? false) || archivedIds.contains(sessionId),
            filePath: fileURL,
            fileModDate: mdate,
            transcriptPath: transcript?.url,
            transcriptSizeBytes: transcript?.size,
            isLiveRunning: isLive
        )
    }

    private struct ArchivedIndexFile: Decodable {
        let archived: [String]?
    }

    private func readArchivedIds(in orgDir: URL) -> Set<String> {
        let idxURL = orgDir.appendingPathComponent("archived-sessions.idx")
        guard let data = try? Data(contentsOf: idxURL),
              let decoded = try? JSONDecoder().decode(ArchivedIndexFile.self, from: data) else {
            return []
        }
        return Set(decoded.archived ?? [])
    }

    private struct PlanUsageFile: Decodable {
        struct Sample: Decodable {
            struct Utilization: Decodable {
                let fh: Int?
                let sd: Int?
                let xu: Int?
            }
            let t: Double
            let org: String
            let u: Utilization?
        }
        let samples: [Sample]?
    }

    public func readUsageHistory(in profileDir: URL) -> [String: OrgUsage] {
        let fileURL = profileDir.appendingPathComponent("plan-usage-history.json")
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(PlanUsageFile.self, from: data),
              let samples = decoded.samples else {
            return [:]
        }

        var grouped: [String: [UsageSamplePoint]] = [:]
        for sample in samples {
            let point = UsageSamplePoint(
                timestamp: Date(timeIntervalSince1970: sample.t / 1000.0),
                fiveHour: sample.u?.fh,
                sevenDay: sample.u?.sd,
                extraUsage: sample.u?.xu
            )
            grouped[sample.org, default: []].append(point)
        }

        var result: [String: OrgUsage] = [:]
        for (org, points) in grouped {
            let sorted = points.sorted { $0.timestamp < $1.timestamp }
            guard let latest = sorted.last else { continue }
            let recentFiveHour: Int?
            if let fh = latest.fiveHour {
                recentFiveHour = fh
            } else {
                let cutoff = latest.timestamp.addingTimeInterval(-4.5 * 3600)
                recentFiveHour = sorted.reversed().first { $0.timestamp >= cutoff && $0.fiveHour != nil }?.fiveHour
            }
            let latestSevenDay = latest.sevenDay ?? sorted.reversed().first { $0.sevenDay != nil }?.sevenDay
            let latestExtra = latest.extraUsage

            result[org] = OrgUsage(
                orgUuid: org,
                fiveHourPercent: recentFiveHour,
                sevenDayPercent: latestSevenDay,
                extraUsagePercent: latestExtra,
                updatedAt: latest.timestamp,
                history: Array(sorted.suffix(40)),
                lastRateLimitHit: nil
            )
        }
        return result
    }

    private func localSessionFiles(in dir: URL, fm: FileManager) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("local_") && name.hasSuffix(".json")
        }
    }

    private func subdirectories(at url: URL, fm: FileManager) -> [URL] {
        guard let entries = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.filter { entry in
            (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
    }

    private func modDate(of url: URL, fm: FileManager) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func isLikelyUUID(_ s: String) -> Bool {
        UUID(uuidString: s) != nil
    }
}
