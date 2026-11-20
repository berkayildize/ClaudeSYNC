import Foundation

public final class SessionDiscovery: @unchecked Sendable {
    public let claudeProjectsDir: URL
    public let rateLimitWatcher: RateLimitWatcher

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

    public init(
        claudeProjectsDir: URL = SessionDiscovery.defaultClaudeProjectsDir,
        rateLimitWatcher: RateLimitWatcher = RateLimitWatcher()
    ) {
        self.claudeProjectsDir = claudeProjectsDir
        self.rateLimitWatcher = rateLimitWatcher
    }

    public static var defaultClaudeProjectsDir: URL {
        URL(fileURLWithPath: ("~/.claude/projects" as NSString).expandingTildeInPath, isDirectory: true)
    }

    public func discoverAccounts(
        profiles: [ProfileConfig],
        nicknames: [String: String],
        processSnapshot: ProcessSnapshot
    ) -> [AccountSlot] {
        let fm = FileManager.default
        let transcriptIndex = buildTranscriptIndex(fm: fm)

        // Merge plan-usage-history.json across ALL profiles so every org gets its freshest reading + full timeline
        var mergedUsageByOrg: [String: OrgUsage] = [:]
        for profile in profiles {
            let perProfile = readUsageHistory(in: profile.expandedURL.standardizedFileURL)
            for (org, usage) in perProfile {
                if let existing = mergedUsageByOrg[org] {
                    let combinedHistory = mergeHistory(existing.history, usage.history)
                    let newer = usage.updatedAt >= existing.updatedAt ? usage : existing
                    mergedUsageByOrg[org] = OrgUsage(
                        orgUuid: org,
                        fiveHourPercent: newer.fiveHourPercent,
                        sevenDayPercent: newer.sevenDayPercent,
                        extraUsagePercent: newer.extraUsagePercent ?? existing.extraUsagePercent,
                        updatedAt: newer.updatedAt,
                        history: combinedHistory,
                        lastRateLimitHit: newer.lastRateLimitHit ?? existing.lastRateLimitHit
                    )
                } else {
                    mergedUsageByOrg[org] = usage
                }
            }
        }

        var result: [AccountSlot] = []
        var defaultCounter = 0

        for profile in profiles {
            let profileDir = profile.expandedURL.standardizedFileURL
            let sessionsRoot = profileDir.appendingPathComponent("claude-code-sessions", isDirectory: true)
            guard fm.fileExists(atPath: sessionsRoot.path) else { continue }

            let runningInstance = processSnapshot.runningInstances.first {
                $0.dataDir == profileDir.path || (profile.isDefault && $0.isDefaultProfile)
            }

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

                    // Cached tail scan for rate-limit events
                    let rateLimitHit = scanLatestRateLimitCached(for: cards, fm: fm)
                    var usage = mergedUsageByOrg[orgUuid]
                    if let hit = rateLimitHit {
                        if var existingUsage = usage {
                            existingUsage.lastRateLimitHit = hit
                            usage = existingUsage
                        } else {
                            usage = OrgUsage(
                                orgUuid: orgUuid,
                                fiveHourPercent: hit.rateLimitType == "five_hour" ? 100 : nil,
                                sevenDayPercent: hit.rateLimitType == "seven_day" ? 100 : nil,
                                extraUsagePercent: nil,
                                updatedAt: hit.timestamp,
                                history: [],
                                lastRateLimitHit: hit
                            )
                        }
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
                            let lUsageDate = profileSlots[lhs].usage?.updatedAt ?? .distantPast
                            let rUsageDate = profileSlots[rhs].usage?.updatedAt ?? .distantPast
                            if abs(lUsageDate.timeIntervalSince(rUsageDate)) > 5 {
                                return lUsageDate < rUsageDate
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

        // Deduplicate: if an accountOrgKey has a dedicated secondary profile, hide stale inactive copy from default profile
        let dedicatedSecondaryKeys = Set(result.filter { !$0.isDefaultProfile }.map(\.accountOrgKey))
        if !dedicatedSecondaryKeys.isEmpty {
            result = result.filter { slot in
                if slot.isDefaultProfile && dedicatedSecondaryKeys.contains(slot.accountOrgKey) && !slot.isActiveAccount {
                    return false
                }
                return true
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
