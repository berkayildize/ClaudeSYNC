import Foundation

public enum SyncEngineError: LocalizedError {
    case sameSourceAndTarget
    case invalidSourceJSON(String)
    case missingSourceFile(String)
    case destinationDirectoryMissing(String)

    public var errorDescription: String? {
        switch self {
        case .sameSourceAndTarget:
            return "Kaynak ve hedef hesap aynı olamaz."
        case .invalidSourceJSON(let path):
            return "Session JSON dosyası okunamadı: \(path)"
        case .missingSourceFile(let path):
            return "Kaynak session dosyası bulunamadı: \(path)"
        case .destinationDirectoryMissing(let path):
            return "Hedef hesap klasörü bulunamadı: \(path)"
        }
    }
}

public struct SessionSyncEngine: Sendable {
    public let backupRootDir: URL
    public let maxBackupCount: Int

    public init(
        backupRootDir: URL = Self.defaultBackupRootDir,
        maxBackupCount: Int = 30
    ) {
        self.backupRootDir = backupRootDir
        self.maxBackupCount = maxBackupCount
    }

    public static var defaultBackupRootDir: URL {
        URL(
            fileURLWithPath: ("~/Library/Application Support/ClaudeSYNC/backups" as NSString)
                .expandingTildeInPath,
            isDirectory: true
        )
    }

    public func computeRelation(session: ClaudeSessionCard, in target: AccountSlot) -> SyncRelation {
        let match = target.sessions.first { candidate in
            candidate.sessionId == session.sessionId ||
            (session.cliSessionId != nil && candidate.cliSessionId == session.cliSessionId)
        }

        guard let targetSession = match else {
            return .onlyInSource
        }

        let deltaTurns = session.completedTurns - targetSession.completedTurns
        if deltaTurns > 0 {
            return .sourceNewer(deltaTurns: deltaTurns)
        }
        if deltaTurns < 0 {
            return .targetNewer(deltaTurns: abs(deltaTurns))
        }

        let timeDiff = session.activityTimestamp.timeIntervalSince(targetSession.activityTimestamp)
        if timeDiff > 2.0 {
            return .sourceNewer(deltaTurns: 0)
        }
        if timeDiff < -2.0 {
            return .targetNewer(deltaTurns: 0)
        }

        // If target had it archived while source is active, offer sync
        if !session.isArchived && targetSession.isArchived {
            return .sourceNewer(deltaTurns: 0)
        }

        return .inSync
    }

    public func transferSession(
        _ session: ClaudeSessionCard,
        from source: AccountSlot,
        to target: AccountSlot,
        options: TransferOptions = TransferOptions(),
        sharedBackupDir: URL? = nil
    ) throws -> TransferResult {
        let fm = FileManager.default
        let sourceDirStd = source.sessionsDir.standardizedFileURL
        let targetDirStd = target.sessionsDir.standardizedFileURL
        guard sourceDirStd != targetDirStd else {
            throw SyncEngineError.sameSourceAndTarget
        }
        guard fm.fileExists(atPath: session.filePath.path) else {
            throw SyncEngineError.missingSourceFile(session.filePath.path)
        }
        guard fm.fileExists(atPath: targetDirStd.path) else {
            throw SyncEngineError.destinationDirectoryMissing(targetDirStd.path)
        }

        let rawData = try Data(contentsOf: session.filePath)
        guard var jsonObj = try JSONSerialization.jsonObject(with: rawData, options: []) as? [String: Any] else {
            throw SyncEngineError.invalidSourceJSON(session.filePath.path)
        }

        var notes: [String] = []

        if options.clearBridgeIds {
            if let existing = jsonObj["bridgeSessionIds"] as? [Any], !existing.isEmpty {
                notes.append("Bulut bridge ID'leri temizlendi")
            }
            jsonObj["bridgeSessionIds"] = []
        }

        if options.clearRemoteMcp {
            if let existing = jsonObj["remoteMcpServersConfig"] as? [Any], !existing.isEmpty {
                notes.append("Uzak MCP connector eşleşmeleri hedef hesap için sıfırlandı")
            }
            jsonObj["remoteMcpServersConfig"] = []
        }

        if options.unarchiveInTarget {
            jsonObj["isArchived"] = false
        }

        if options.bumpLastFocusedAt {
            jsonObj["lastFocusedAt"] = Int64(Date().timeIntervalSince1970 * 1000.0)
        }

        let destinationFile = targetDirStd.appendingPathComponent(session.filePath.lastPathComponent)
        let tombstoneFile = targetDirStd.appendingPathComponent("deleted_\(session.uuidSuffix)")
        let archivedIdxFile = targetDirStd.appendingPathComponent("archived-sessions.idx")

        var createdBackupDir: URL? = sharedBackupDir
        func ensureBackupDir() throws -> URL {
            if let existing = createdBackupDir {
                try fm.createDirectory(at: existing, withIntermediateDirectories: true)
                return existing
            }
            let dir = makeTimestampedBackupDir()
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            createdBackupDir = dir
            return dir
        }

        // 1. Backup existing target session file if overwriting
        if fm.fileExists(atPath: destinationFile.path) {
            let bDir = try ensureBackupDir()
            try backupFile(destinationFile, toDir: bDir, prefix: target.shortAccountTag, fm: fm)
            notes.append("Hedefteki eski kopya yedeklendi")
        }

        // 2. Serialize and atomically write with 0600 permissions
        let outData = try JSONSerialization.data(withJSONObject: jsonObj, options: [.sortedKeys])
        try atomicWritePrivateFile(data: outData, to: destinationFile, fm: fm)

        // 3. Remove deleted_<uuid> tombstone in target if present
        if fm.fileExists(atPath: tombstoneFile.path) {
            let bDir = try ensureBackupDir()
            try backupFile(tombstoneFile, toDir: bDir, prefix: target.shortAccountTag, fm: fm)
            try fm.removeItem(at: tombstoneFile)
            notes.append("Hedefteki silinmiş işareti (deleted_\(String(session.uuidSuffix.prefix(6)))) kaldırıldı")
        }

        // 4. Remove from target archived-sessions.idx if present & unarchiveInTarget
        if options.unarchiveInTarget && fm.fileExists(atPath: archivedIdxFile.path) {
            if try removeFromArchivedIndexIfNeeded(
                sessionId: session.sessionId,
                indexFile: archivedIdxFile,
                ensureBackup: ensureBackupDir,
                backupPrefix: target.shortAccountTag,
                fm: fm
            ) {
                notes.append("Hedef hesabın arşiv listesinden çıkarıldı")
            }
        }

        // 5. Cross-profile worktree metadata merge if applicable
        let wasCrossProfile = source.profileDataDir.standardizedFileURL != target.profileDataDir.standardizedFileURL
        if wasCrossProfile && options.mergeWorktreeIfNeeded && session.isWorktree {
            let merged = try mergeGitWorktreesMetadata(
                fromProfile: source.profileDataDir,
                toProfile: target.profileDataDir,
                ensureBackup: ensureBackupDir,
                fm: fm
            )
            if merged {
                notes.append("Worktree kaydı hedef profile eklendi")
            }
        }

        if sharedBackupDir == nil && createdBackupDir != nil {
            pruneOldBackups(fm: fm)
        }

        return TransferResult(
            sessionId: session.sessionId,
            title: session.title,
            sourceName: source.displayName,
            targetName: target.displayName,
            destinationFile: destinationFile,
            backupDir: createdBackupDir,
            notes: notes,
            wasCrossProfile: wasCrossProfile
        )
    }

    public func syncAllActive(
        from accountA: AccountSlot,
        to accountB: AccountSlot,
        bidirectional: Bool = true,
        options: TransferOptions = TransferOptions()
    ) throws -> BatchSyncSummary {
        guard accountA.sessionsDir.standardizedFileURL != accountB.sessionsDir.standardizedFileURL else {
            throw SyncEngineError.sameSourceAndTarget
        }

        var bulkOptions = options
        bulkOptions.bumpLastFocusedAt = false // Preserve sidebar recency ordering on bulk sync

        let sharedBackup = makeTimestampedBackupDir()
        var copied = 0
        var updated = 0
        var skippedUpToDate = 0
        var skippedTargetNewer = 0
        var errors: [String] = []
        var usedBackup = false

        func runDirection(src: AccountSlot, dst: AccountSlot, countEqual: Bool) {
            for session in src.activeSessions {
                let relation = computeRelation(session: session, in: dst)
                switch relation {
                case .onlyInSource:
                    do {
                        let res = try transferSession(
                            session,
                            from: src,
                            to: dst,
                            options: bulkOptions,
                            sharedBackupDir: sharedBackup
                        )
                        if res.backupDir != nil && FileManager.default.fileExists(atPath: sharedBackup.path) {
                            usedBackup = true
                        }
                        copied += 1
                    } catch {
                        errors.append("\(session.title): \(error.localizedDescription)")
                    }

                case .sourceNewer:
                    do {
                        let res = try transferSession(
                            session,
                            from: src,
                            to: dst,
                            options: bulkOptions,
                            sharedBackupDir: sharedBackup
                        )
                        if res.backupDir != nil && FileManager.default.fileExists(atPath: sharedBackup.path) {
                            usedBackup = true
                        }
                        updated += 1
                    } catch {
                        errors.append("\(session.title): \(error.localizedDescription)")
                    }

                case .inSync:
                    if countEqual { skippedUpToDate += 1 }

                case .targetNewer:
                    if !bidirectional { skippedTargetNewer += 1 }
                }
            }
        }

        runDirection(src: accountA, dst: accountB, countEqual: true)
        if bidirectional {
            runDirection(src: accountB, dst: accountA, countEqual: false)
        }

        let fm = FileManager.default
        let actualBackupDir: URL?
        if usedBackup && fm.fileExists(atPath: sharedBackup.path) {
            pruneOldBackups(fm: fm)
            actualBackupDir = sharedBackup
        } else {
            actualBackupDir = nil
        }

        return BatchSyncSummary(
            copiedCount: copied,
            updatedCount: updated,
            skippedUpToDate: skippedUpToDate,
            skippedTargetNewer: skippedTargetNewer,
            backupDir: actualBackupDir,
            errors: errors
        )
    }

    /// Automatically mirrors metadata updates (`completedTurns`, `lastActivityAt`, `title`, etc.)
    /// strictly for sessions that ALREADY exist in both accounts — never copies unshared sessions
    /// and never overwrites a newer card with an older one.
    public func syncSharedCards(
        between accountA: AccountSlot,
        and accountB: AccountSlot,
        liveCliSessionIds: Set<String> = [],
        options: TransferOptions = TransferOptions(),
        now: Date = Date()
    ) throws -> AutoCardSyncSummary {
        guard accountA.sessionsDir.standardizedFileURL != accountB.sessionsDir.standardizedFileURL else {
            return AutoCardSyncSummary(updatedCount: 0, syncedTitles: [], backupDir: nil)
        }

        var mirrorOptions = options
        mirrorOptions.bumpLastFocusedAt = false

        let sharedBackup = makeTimestampedBackupDir()
        var updatedCount = 0
        var syncedTitles: [String] = []
        var usedBackup = false
        let isCrossProfile = accountA.profileDataDir.standardizedFileURL != accountB.profileDataDir.standardizedFileURL

        func mirrorNewerShared(from src: AccountSlot, to dst: AccountSlot) {
            for session in src.activeSessions {
                guard let dstMatch = dst.sessions.first(where: { candidate in
                    candidate.sessionId == session.sessionId ||
                    (session.cliSessionId != nil && candidate.cliSessionId == session.cliSessionId)
                }) else {
                    continue
                }

                // Skip if destination is actively writing to this exact session right now
                if let cliId = dstMatch.cliSessionId?.lowercased(),
                   liveCliSessionIds.contains(cliId),
                   isCrossProfile,
                   dst.runningPid != nil,
                   now.timeIntervalSince(dstMatch.fileModDate) < 10.0 {
                    continue
                }

                // In single-app mode, only write into the inactive account so we never race Claude Desktop
                if !isCrossProfile && dst.isActiveAccount && !src.isActiveAccount {
                    continue
                }

                let rel = computeRelation(session: session, in: dst)
                guard case .sourceNewer = rel else { continue }

                if let res = try? transferSession(
                    session,
                    from: src,
                    to: dst,
                    options: mirrorOptions,
                    sharedBackupDir: sharedBackup
                ) {
                    if res.backupDir != nil && FileManager.default.fileExists(atPath: sharedBackup.path) {
                        usedBackup = true
                    }
                    updatedCount += 1
                    syncedTitles.append(session.title)
                }
            }
        }

        mirrorNewerShared(from: accountA, to: accountB)
        mirrorNewerShared(from: accountB, to: accountA)

        let fm = FileManager.default
        let actualBackup: URL?
        if usedBackup && fm.fileExists(atPath: sharedBackup.path) {
            pruneOldBackups(fm: fm)
            actualBackup = sharedBackup
        } else {
            actualBackup = nil
        }

        return AutoCardSyncSummary(
            updatedCount: updatedCount,
            syncedTitles: syncedTitles,
            backupDir: actualBackup
        )
    }

    public func initializeSecondaryProfile(
        at targetDataDir: URL,
        copyMcpConfigFrom sourceDataDir: URL?,
        migrateAccountSessionsFrom accountToMigrate: AccountSlot? = nil
    ) throws -> Bool {
        let fm = FileManager.default
        try fm.createDirectory(at: targetDataDir, withIntermediateDirectories: true)

        var copiedMcp = false
        if let srcDir = sourceDataDir {
            let srcConfig = srcDir.appendingPathComponent("claude_desktop_config.json")
            let dstConfig = targetDataDir.appendingPathComponent("claude_desktop_config.json")
            if fm.fileExists(atPath: srcConfig.path) && !fm.fileExists(atPath: dstConfig.path) {
                try fm.copyItem(at: srcConfig, to: dstConfig)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dstConfig.path)
                copiedMcp = true
            }

            let srcWorktrees = srcDir.appendingPathComponent("git-worktrees.json")
            let dstWorktrees = targetDataDir.appendingPathComponent("git-worktrees.json")
            if fm.fileExists(atPath: srcWorktrees.path) && !fm.fileExists(atPath: dstWorktrees.path) {
                try? fm.copyItem(at: srcWorktrees, to: dstWorktrees)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dstWorktrees.path)
            }
        }

        // Pre-populate existing session cards for the target account so zero history is lost on first login
        if let acc = accountToMigrate {
            let dstOrgDir = targetDataDir
                .appendingPathComponent("claude-code-sessions", isDirectory: true)
                .appendingPathComponent(acc.accountUuid, isDirectory: true)
                .appendingPathComponent(acc.orgUuid, isDirectory: true)
            try fm.createDirectory(at: dstOrgDir, withIntermediateDirectories: true)

            let dummyTarget = AccountSlot(
                profileId: "new-secondary",
                profileName: "2. Profil",
                profileDataDir: targetDataDir,
                isDefaultProfile: false,
                accountUuid: acc.accountUuid,
                orgUuid: acc.orgUuid,
                sessionsDir: dstOrgDir,
                displayName: acc.displayName,
                sessions: [],
                archivedIds: [],
                usage: nil,
                isActiveAccount: false,
                runningPid: nil
            )
            let migrateOpts = TransferOptions(
                clearBridgeIds: false, // Same account!
                clearRemoteMcp: false, // Same account!
                bumpLastFocusedAt: false,
                unarchiveInTarget: false,
                mergeWorktreeIfNeeded: false
            )
            for session in acc.activeSessions {
                let dstFile = dstOrgDir.appendingPathComponent(session.filePath.lastPathComponent)
                if !fm.fileExists(atPath: dstFile.path) {
                    _ = try? transferSession(session, from: acc, to: dummyTarget, options: migrateOpts)
                }
            }
        }

        return copiedMcp
    }

    // MARK: - Internal Helpers

    private func makeTimestampedBackupDir() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: Date())
        return backupRootDir.appendingPathComponent(stamp, isDirectory: true)
    }

    private func backupFile(_ file: URL, toDir backupDir: URL, prefix: String, fm: FileManager) throws {
        var dest = backupDir.appendingPathComponent("\(prefix)_\(file.lastPathComponent)")
        var counter = 1
        while fm.fileExists(atPath: dest.path) {
            dest = backupDir.appendingPathComponent("\(prefix)_\(counter)_\(file.lastPathComponent)")
            counter += 1
        }
        try fm.copyItem(at: file, to: dest)
    }

    private func atomicWritePrivateFile(data: Data, to destination: URL, fm: FileManager) throws {
        let dir = destination.deletingLastPathComponent()
        let tmpName = ".csb_tmp_\(UUID().uuidString)"
        let tmpURL = dir.appendingPathComponent(tmpName)
        do {
            try data.write(to: tmpURL, options: [])
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmpURL.path)
            if fm.fileExists(atPath: destination.path) {
                _ = try fm.replaceItemAt(destination, withItemAt: tmpURL)
            } else {
                try fm.moveItem(at: tmpURL, to: destination)
            }
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        } catch {
            try? fm.removeItem(at: tmpURL)
            throw error
        }
    }

    private func removeFromArchivedIndexIfNeeded(
        sessionId: String,
        indexFile: URL,
        ensureBackup: () throws -> URL,
        backupPrefix: String,
        fm: FileManager
    ) throws -> Bool {
        let data = try Data(contentsOf: indexFile)
        guard var obj = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              var archived = obj["archived"] as? [String],
              archived.contains(sessionId) else {
            return false
        }

        let bDir = try ensureBackup()
        try backupFile(indexFile, toDir: bDir, prefix: backupPrefix, fm: fm)

        archived.removeAll { $0 == sessionId }
        obj["archived"] = archived
        let outData = try JSONSerialization.data(withJSONObject: obj, options: [])
        try atomicWritePrivateFile(data: outData, to: indexFile, fm: fm)
        return true
    }

    private func mergeGitWorktreesMetadata(
        fromProfile sourceProfile: URL,
        toProfile targetProfile: URL,
        ensureBackup: () throws -> URL,
        fm: FileManager
    ) throws -> Bool {
        let srcFile = sourceProfile.appendingPathComponent("git-worktrees.json")
        guard fm.fileExists(atPath: srcFile.path),
              let srcData = try? Data(contentsOf: srcFile),
              let srcObj = try? JSONSerialization.jsonObject(with: srcData) as? [String: Any] else {
            return false
        }

        let dstFile = targetProfile.appendingPathComponent("git-worktrees.json")
        if !fm.fileExists(atPath: dstFile.path) {
            try atomicWritePrivateFile(data: srcData, to: dstFile, fm: fm)
            return true
        }

        guard let dstData = try? Data(contentsOf: dstFile),
              var dstObj = try? JSONSerialization.jsonObject(with: dstData) as? [String: Any] else {
            return false
        }

        var changed = false
        for dictKey in ["worktrees", "originUrls", "originPins"] {
            guard let srcDict = srcObj[dictKey] as? [String: Any] else { continue }
            var dstDict = (dstObj[dictKey] as? [String: Any]) ?? [:]
            for (k, v) in srcDict where dstDict[k] == nil {
                dstDict[k] = v
                changed = true
            }
            dstObj[dictKey] = dstDict
        }

        guard changed else { return false }
        let bDir = try ensureBackup()
        try backupFile(dstFile, toDir: bDir, prefix: "profile", fm: fm)
        let mergedData = try JSONSerialization.data(withJSONObject: dstObj, options: [.sortedKeys])
        try atomicWritePrivateFile(data: mergedData, to: dstFile, fm: fm)
        return true
    }

    private func pruneOldBackups(fm: FileManager) {
        guard maxBackupCount > 0,
              let entries = try? fm.contentsOfDirectory(
                  at: backupRootDir,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else { return }

        let dirs = entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }

        if dirs.count > maxBackupCount {
            for old in dirs.dropFirst(maxBackupCount) {
                try? fm.removeItem(at: old)
            }
        }
    }
}
