import Foundation

public struct RateLimitWatcher: Sendable {
    public let tailBytesLimit: UInt64

    public init(tailBytesLimit: UInt64 = 180_000) {
        self.tailBytesLimit = tailBytesLimit
    }

    /// Reads only the tail of recent session `.jsonl` files to extract the latest rate-limit / quota rejection event.
    public func scanLatestRateLimit(
        for sessions: [ClaudeSessionCard],
        maxSessions: Int = 10
    ) -> RateLimitEvent? {
        let candidates = sessions
            .filter { $0.transcriptPath != nil }
            .prefix(maxSessions)

        var latest: RateLimitEvent?
        for session in candidates {
            guard let path = session.transcriptPath,
                  let cliId = session.cliSessionId,
                  let event = parseTailForRateLimit(fileURL: path, cliSessionId: cliId) else {
                continue
            }
            if let existing = latest {
                if event.timestamp > existing.timestamp {
                    latest = event
                }
            } else {
                latest = event
            }
        }
        return latest
    }

    public func parseTailForRateLimit(fileURL: URL, cliSessionId: String) -> RateLimitEvent? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        let fileSize: UInt64
        do {
            fileSize = try handle.seekToEnd()
        } catch {
            return nil
        }

        let startOffset = fileSize > tailBytesLimit ? (fileSize - tailBytesLimit) : 0
        do {
            try handle.seek(toOffset: startOffset)
        } catch {
            return nil
        }

        let data: Data
        do {
            data = try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        let effectiveLines = startOffset > 0 ? Array(lines.dropFirst()) : Array(lines)

        // Walk backwards so we find the most recent event immediately
        for rawLine in effectiveLines.reversed() {
            if !rawLine.contains("quotaLimits") && !rawLine.contains("usage_limit_reached") {
                continue
            }
            guard let lineData = rawLine.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
                continue
            }

            let quotaDict = (obj["quotaLimits"] as? [String: Any])
                ?? ((obj["apiErrorParams"] as? [String: Any])?["rate_limit_info"] as? [String: Any])

            let apiError = obj["apiError"] as? String
            let apiStatus = obj["apiErrorStatus"] as? Int
            let status = (quotaDict?["status"] as? String)
                ?? ((apiError == "usage_limit_reached" || apiStatus == 429) ? "rejected" : nil)

            guard let resolvedStatus = status else { continue }

            let rateLimitType = (quotaDict?["rateLimitType"] as? String) ?? "unknown"
            let resetsAtSec: Double?
            if let d = quotaDict?["resetsAt"] as? Double {
                resetsAtSec = d
            } else if let i = quotaDict?["resetsAt"] as? Int {
                resetsAtSec = Double(i)
            } else {
                resetsAtSec = nil
            }
            let resetsAtDate = resetsAtSec.map { Date(timeIntervalSince1970: $0) }

            let eventDate: Date
            if let tsStr = obj["timestamp"] as? String, let parsed = parseISO8601(tsStr) {
                eventDate = parsed
            } else {
                eventDate = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date) ?? Date()
            }

            return RateLimitEvent(
                timestamp: eventDate,
                rateLimitType: rateLimitType,
                resetsAt: resetsAtDate,
                status: resolvedStatus,
                cliSessionId: cliSessionId
            )
        }

        return nil
    }

    public func evaluateAutoSwitch(
        accounts: [AccountSlot],
        settings: BridgeSettings,
        lastHandledEventKey: String?,
        now: Date = Date()
    ) -> AutoSwitchDecision? {
        guard settings.autoSwitchEnabled, accounts.count >= 2 else { return nil }
        guard let source = accounts.first(where: { $0.isActiveAccount }) ?? accounts.first else { return nil }
        guard let usage = source.usage else { return nil }

        // Determine if source has triggered an automatic switch event
        let isTr = settings.language.resolvedIsTurkish
        var triggerReason: String?
        var eventKey: String?

        // Check fresh 429 rejection (within last 10 minutes)
        if let hit = usage.lastRateLimitHit,
           hit.isCurrentlyRejected,
           now.timeIntervalSince(hit.timestamp) <= 10 * 60 {
            let label = hit.rateLimitTypeLabel(isTurkish: isTr)
            triggerReason = isTr
                ? "\(source.displayName) \(label.lowercased()) doldu (429)"
                : "\(source.displayName) hit \(label.lowercased()) (429)"
            eventKey = "\(source.accountOrgKey)|429|\(hit.eventKey)"
        }

        // Check threshold triggers if not already triggered by 429
        if triggerReason == nil && settings.autoSwitchTrigger != .onRateLimitError {
            let threshold = (settings.autoSwitchTrigger == .at95Percent) ? 95 : 100
            let sampleIsFresh = now.timeIntervalSince(usage.updatedAt) <= 20 * 60
            if sampleIsFresh && usage.peakPercent >= threshold {
                let isFiveHour = (usage.fiveHourPercent ?? 0) >= threshold
                if isTr {
                    let windowLabel = isFiveHour ? "5 saatlik" : "7 günlük"
                    triggerReason = "\(source.displayName) \(windowLabel) limiti %\(usage.peakPercent) seviyesine ulaştı"
                } else {
                    let windowLabel = isFiveHour ? "5-hour" : "7-day"
                    triggerReason = "\(source.displayName) \(windowLabel) usage reached \(usage.peakPercent)%"
                }
                let bucket = Int(usage.updatedAt.timeIntervalSince1970 / 300) // 5-min dedup bucket
                eventKey = "\(source.accountOrgKey)|pct\(threshold)|\(bucket)"
            }
        }

        guard let reason = triggerReason, let key = eventKey else { return nil }
        if lastHandledEventKey == key {
            return nil
        }

        // Find best healthy alternate account (prefer separate --user-data-dir profile + lowest usage)
        let candidates = accounts.filter { $0.id != source.id }
        let healthyCandidates = candidates.filter { candidate in
            guard let u = candidate.usage else { return true }
            return !u.isExhausted && (u.fiveHourPercent ?? 0) < 95 && (u.sevenDayPercent ?? 0) < 100
        }

        guard let target = healthyCandidates.sorted(by: { a, b in
            let aCross = a.profileDataDir.standardizedFileURL != source.profileDataDir.standardizedFileURL
            let bCross = b.profileDataDir.standardizedFileURL != source.profileDataDir.standardizedFileURL
            if aCross != bCross { return aCross && !bCross }
            return (a.usage?.peakPercent ?? 0) < (b.usage?.peakPercent ?? 0)
        }).first else {
            return nil
        }

        let sessionsToMove: [ClaudeSessionCard]
        if settings.autoSwitchTransferAllLive && !source.liveSessions.isEmpty {
            sessionsToMove = source.liveSessions
        } else if let top = source.liveSessions.first ?? source.activeSessions.first {
            sessionsToMove = [top]
        } else {
            sessionsToMove = []
        }

        let isZeroLogoutReady = source.profileDataDir.standardizedFileURL != target.profileDataDir.standardizedFileURL

        return AutoSwitchDecision(
            source: source,
            target: target,
            sessionsToTransfer: sessionsToMove,
            reason: reason,
            eventKey: key,
            isZeroLogoutReady: isZeroLogoutReady
        )
    }

    private func parseISO8601(_ str: String) -> Date? {
        let withFrac = ISO8601DateFormatter()
        withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFrac.date(from: str) { return d }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: str)
    }
}
