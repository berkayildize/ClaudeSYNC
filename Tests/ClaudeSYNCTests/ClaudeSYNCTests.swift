import ClaudeSYNCCore
import Foundation
import XCTest

final class ClaudeSYNCTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeSYNCTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - ProcessMonitor Parsing Tests

    func testParsePsOutputExtractsInstancesLiveSessionsAndActivePairs() {
        let defaultDir = "/Users/test/Library/Application Support/Claude"
        let ps = """
          PID ARGS
        50167 /Applications/Claude.app/Contents/MacOS/Claude
        51000 /Applications/Claude.app/Contents/MacOS/Claude --user-data-dir=/Users/test/Library/Application Support/Claude-Account2 --enable-features=Foo
        51621 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper
        51653 /Users/test/Library/Application Support/Claude/claude-code/2.1.326/claude --output-format stream-json --resume=FFFFFFFF-6666-4000-8000-000000000001 --verbose
        52529 /opt/homebrew/bin/python3 /Users/test/Library/Application Support/Claude/local-agent-mode-sessions/aaaaaaaa-1111-4000-8000-000000000001/bbbbbbbb-2222-4000-8000-000000000001/rpm/server.py
        """

        let snap = ProcessMonitor.parsePsOutput(ps, defaultDataDir: defaultDir)
        XCTAssertEqual(snap.runningInstances.count, 2)
        XCTAssertTrue(snap.runningInstances.contains { $0.pid == 50167 && $0.isDefaultProfile })
        XCTAssertTrue(snap.runningInstances.contains {
            $0.pid == 51000 &&
            !$0.isDefaultProfile &&
            $0.dataDir == "/Users/test/Library/Application Support/Claude-Account2"
        })
        XCTAssertEqual(snap.liveCliSessionIds, ["ffffffff-6666-4000-8000-000000000001"])
        XCTAssertEqual(
            snap.activeAccountOrgPairs,
            ["aaaaaaaa-1111-4000-8000-000000000001/bbbbbbbb-2222-4000-8000-000000000001"]
        )
    }

    // MARK: - SessionDiscovery Tests

    func testDiscoveryFiltersStubOrgsMatchesTranscriptsAndReadsUsage() throws {
        let fm = FileManager.default
        let profileDir = tempRoot.appendingPathComponent("Claude", isDirectory: true)
        let projectsDir = tempRoot.appendingPathComponent("projects", isDirectory: true)

        let acc1 = "aaaaaaaa-1111-4000-8000-000000000001"
        let org1 = "bbbbbbbb-2222-4000-8000-000000000001"
        let acc2 = "cccccccc-3333-4000-8000-000000000002"
        let org2 = "dddddddd-4444-4000-8000-000000000002"

        let acc1Org1 = profileDir.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let acc1StubOrg2 = profileDir.appendingPathComponent("claude-code-sessions/\(acc1)/\(org2)", isDirectory: true)
        let acc2Org2 = profileDir.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        let acc2StubOrg1 = profileDir.appendingPathComponent("claude-code-sessions/\(acc2)/\(org1)", isDirectory: true)

        for dir in [acc1Org1, acc1StubOrg2, acc2Org2, acc2StubOrg1] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        // Stub dirs contain only scheduled-tasks.json
        try Data("{}".utf8).write(to: acc1StubOrg2.appendingPathComponent("scheduled-tasks.json"))
        try Data("{}".utf8).write(to: acc2StubOrg1.appendingPathComponent("scheduled-tasks.json"))

        // Real session cards
        let cli1 = "eeeeeeee-5555-4000-8000-000000000001"
        let cli2 = "11111111-2222-3333-4444-555555555555"
        try writeSessionJSON(
            in: acc1Org1,
            sessionId: "local_aaaa0000-0000-0000-0000-000000000001",
            cliSessionId: cli1,
            title: "Ana Proje",
            cwd: "/Users/test/Desktop/app",
            turns: 42,
            lastActivityMs: 1_795_000_000_000
        )
        try writeSessionJSON(
            in: acc2Org2,
            sessionId: "local_bbbb0000-0000-0000-0000-000000000002",
            cliSessionId: cli2,
            title: "İkinci Hesap İşi",
            cwd: "/Users/test/Desktop/app",
            turns: 12,
            lastActivityMs: 1_794_000_000_000
        )

        // Shared ~/.claude/projects transcript
        let projDir = projectsDir.appendingPathComponent("-Users-test-Desktop-app", isDirectory: true)
        try fm.createDirectory(at: projDir, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 4096).write(to: projDir.appendingPathComponent("\(cli1).jsonl"))

        // plan-usage-history.json
        let usageJSON = """
        {"version":2,"samples":[
          {"t":1794000000000,"org":"\(org1)","u":{"fh":20,"sd":50}},
          {"t":1795000000000,"org":"\(org1)","u":{"fh":95,"sd":100}},
          {"t":1794500000000,"org":"\(org2)","u":{"fh":8,"sd":40}}
        ]}
        """
        try Data(usageJSON.utf8).write(to: profileDir.appendingPathComponent("plan-usage-history.json"))

        let discovery = SessionDiscovery(claudeProjectsDir: projectsDir)
        let profile = ProfileConfig(id: "default", name: "Ana Profil", dataDirPath: profileDir.path, isDefault: true)
        let snap = ProcessSnapshot(
            runningInstances: [RunningClaudeInstance(pid: 999, dataDir: profileDir.path, isDefaultProfile: true)],
            liveCliSessionIds: [cli1],
            activeAccountOrgPairs: ["\(acc1)/\(org1)"]
        )

        let accounts = discovery.discoverAccounts(
            profiles: [profile],
            nicknames: ["\(acc1)/\(org1)": "Ultra 1"],
            processSnapshot: snap
        )

        // Must discover ONLY the 2 real accounts, filtering out the 2 cross-account stubs
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts[0].accountUuid, acc1)
        XCTAssertEqual(accounts[0].orgUuid, org1)
        XCTAssertEqual(accounts[0].displayName, "Ultra 1")
        XCTAssertTrue(accounts[0].isActiveAccount)
        XCTAssertEqual(accounts[0].usage?.fiveHourPercent, 95)
        XCTAssertEqual(accounts[0].usage?.sevenDayPercent, 100)
        XCTAssertEqual(accounts[0].sessions.first?.isLiveRunning, true)
        XCTAssertEqual(accounts[0].sessions.first?.transcriptSizeBytes, 4096)

        XCTAssertEqual(accounts[1].accountUuid, acc2)
        XCTAssertEqual(accounts[1].orgUuid, org2)
        XCTAssertEqual(accounts[1].usage?.fiveHourPercent, 8)
        XCTAssertEqual(accounts[1].usage?.sevenDayPercent, 40)
    }

    func testDiscoveryIncludesBrandNewSecondaryProfileWithZeroSessions() throws {
        let fm = FileManager.default
        let profile2 = tempRoot.appendingPathComponent("Claude-Account2", isDirectory: true)
        let acc = "cccccccc-3333-4000-8000-000000000002"
        let org = "dddddddd-4444-4000-8000-000000000002"
        let orgDir = profile2.appendingPathComponent("claude-code-sessions/\(acc)/\(org)", isDirectory: true)
        try fm.createDirectory(at: orgDir, withIntermediateDirectories: true)

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("empty-projects"))
        let cfg = ProfileConfig(id: "p2", name: "2. Profil", dataDirPath: profile2.path, isDefault: false)
        let accounts = discovery.discoverAccounts(profiles: [cfg], nicknames: [:], processSnapshot: .empty)

        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].sessions.count, 0)
        XCTAssertEqual(accounts[0].accountUuid, acc)
    }

    // MARK: - SessionSyncEngine Tests

    func testTransferSanitizesCleansTombstoneAndArchivedIndexAndBacksUp() throws {
        let fm = FileManager.default
        let profile1 = tempRoot.appendingPathComponent("Profile1", isDirectory: true)
        let profile2 = tempRoot.appendingPathComponent("Profile2", isDirectory: true)
        let backupRoot = tempRoot.appendingPathComponent("Backups", isDirectory: true)

        let acc1 = "11111111-1111-1111-1111-111111111111"
        let org1 = "22222222-2222-2222-2222-222222222222"
        let acc2 = "33333333-3333-3333-3333-333333333333"
        let org2 = "44444444-4444-4444-4444-444444444444"

        let dir1 = profile1.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let dir2 = profile2.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir2, withIntermediateDirectories: true)

        let sessionId = "local_cccc0000-0000-0000-0000-000000000003"
        let uuidSuffix = "cccc0000-0000-0000-0000-000000000003"
        let cliId = "99999999-9999-9999-9999-999999999999"

        // Source card has bridgeSessionIds, remoteMcpServersConfig, customFutureField, and worktree cwd
        let sourceObj: [String: Any] = [
            "sessionId": sessionId,
            "cliSessionId": cliId,
            "title": "Kritik Oturum",
            "cwd": "/Users/test/Desktop/demo-app/.claude/worktrees/wt-1",
            "completedTurns": 88,
            "lastActivityAt": 1_795_000_000_000,
            "lastFocusedAt": 1_794_000_000_000,
            "isArchived": false,
            "bridgeSessionIds": ["session_01ABC"],
            "remoteMcpServersConfig": [["uuid": "x", "name": "Canva"]],
            "customFutureField": ["nested": true]
        ]
        let srcFile = dir1.appendingPathComponent("\(sessionId).json")
        try JSONSerialization.data(withJSONObject: sourceObj).write(to: srcFile)

        // Target already has an older copy, a deleted_<uuid> tombstone, and archived-sessions.idx containing sessionId
        let oldTargetObj: [String: Any] = [
            "sessionId": sessionId,
            "cliSessionId": cliId,
            "title": "Eski Kopya",
            "completedTurns": 10
        ]
        let dstFile = dir2.appendingPathComponent("\(sessionId).json")
        try JSONSerialization.data(withJSONObject: oldTargetObj).write(to: dstFile)

        let tombstone = dir2.appendingPathComponent("deleted_\(uuidSuffix)")
        try Data("1791000000000".utf8).write(to: tombstone)

        let archivedIdx = dir2.appendingPathComponent("archived-sessions.idx")
        try Data(#"{"v":1,"archived":["\#(sessionId)","local_other"]}"#.utf8).write(to: archivedIdx)

        // Worktree metadata in Profile 1 & Profile 2
        let srcWT = #"{"schemaVersion":2,"worktrees":{"wt-1":{"path":"/a"}},"originUrls":{"repo1":"u1"},"originPins":{}}"#
        let dstWT = #"{"schemaVersion":2,"worktrees":{"wt-existing":{"path":"/b"}},"originUrls":{},"originPins":{}}"#
        try Data(srcWT.utf8).write(to: profile1.appendingPathComponent("git-worktrees.json"))
        try Data(dstWT.utf8).write(to: profile2.appendingPathComponent("git-worktrees.json"))

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("projects"))
        let slots = discovery.discoverAccounts(
            profiles: [
                ProfileConfig(id: "p1", name: "P1", dataDirPath: profile1.path, isDefault: true),
                ProfileConfig(id: "p2", name: "P2", dataDirPath: profile2.path, isDefault: false)
            ],
            nicknames: [:],
            processSnapshot: .empty
        )
        let slot1 = try XCTUnwrap(slots.first { $0.accountUuid == acc1 })
        let slot2 = try XCTUnwrap(slots.first { $0.accountUuid == acc2 })
        let session = try XCTUnwrap(slot1.sessions.first)

        let engine = SessionSyncEngine(backupRootDir: backupRoot)
        let res = try engine.transferSession(session, from: slot1, to: slot2, options: TransferOptions())

        // Verify backup was created
        let bDir = try XCTUnwrap(res.backupDir)
        XCTAssertTrue(fm.fileExists(atPath: bDir.path))
        XCTAssertTrue(res.wasCrossProfile)

        // Verify destination JSON sanitized & preserved unknown keys
        let writtenData = try Data(contentsOf: dstFile)
        let writtenObj = try XCTUnwrap(JSONSerialization.jsonObject(with: writtenData) as? [String: Any])
        XCTAssertEqual(writtenObj["completedTurns"] as? Int, 88)
        XCTAssertEqual((writtenObj["bridgeSessionIds"] as? [Any])?.count, 0)
        XCTAssertEqual((writtenObj["remoteMcpServersConfig"] as? [Any])?.count, 0)
        XCTAssertEqual((writtenObj["customFutureField"] as? [String: Bool])?["nested"], true)
        XCTAssertGreaterThan((writtenObj["lastFocusedAt"] as? Int64) ?? 0, 1_794_000_000_000)

        // Verify permissions are 0600
        let attrs = try fm.attributesOfItem(atPath: dstFile.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)

        // Verify tombstone deleted
        XCTAssertFalse(fm.fileExists(atPath: tombstone.path))

        // Verify removed from archived-sessions.idx while preserving other entries
        let idxData = try Data(contentsOf: archivedIdx)
        let idxObj = try XCTUnwrap(JSONSerialization.jsonObject(with: idxData) as? [String: Any])
        XCTAssertEqual(idxObj["archived"] as? [String], ["local_other"])

        // Verify git-worktrees.json merged without overwriting existing entry
        let wtData = try Data(contentsOf: profile2.appendingPathComponent("git-worktrees.json"))
        let wtObj = try XCTUnwrap(JSONSerialization.jsonObject(with: wtData) as? [String: Any])
        let wts = try XCTUnwrap(wtObj["worktrees"] as? [String: Any])
        XCTAssertNotNil(wts["wt-1"])
        XCTAssertNotNil(wts["wt-existing"])
    }

    func testBidirectionalSyncNeverOverwritesNewerAndSkipsArchived() throws {
        let fm = FileManager.default
        let profile = tempRoot.appendingPathComponent("Claude", isDirectory: true)
        let acc1 = "11111111-1111-1111-1111-111111111111"
        let org1 = "22222222-2222-2222-2222-222222222222"
        let acc2 = "33333333-3333-3333-3333-333333333333"
        let org2 = "44444444-4444-4444-4444-444444444444"

        let dir1 = profile.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let dir2 = profile.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir2, withIntermediateDirectories: true)

        // Session A: only in acc1 (active) -> should copy to acc2
        try writeSessionJSON(in: dir1, sessionId: "local_a", cliSessionId: "cli-a", title: "Only A", cwd: "/tmp", turns: 5, lastActivityMs: 1000)
        // Session B: in both, acc2 is NEWER (20 turns vs 10 turns) -> acc2 should update acc1, NOT reverse!
        try writeSessionJSON(in: dir1, sessionId: "local_b", cliSessionId: "cli-b", title: "Shared Older", cwd: "/tmp", turns: 10, lastActivityMs: 1000)
        try writeSessionJSON(in: dir2, sessionId: "local_b", cliSessionId: "cli-b", title: "Shared Newer", cwd: "/tmp", turns: 20, lastActivityMs: 2000)
        // Session C: archived in acc1 -> should be skipped!
        try writeSessionJSON(in: dir1, sessionId: "local_c", cliSessionId: "cli-c", title: "Archived", cwd: "/tmp", turns: 3, lastActivityMs: 1000, isArchived: true)

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("projects"))
        let slots = discovery.discoverAccounts(
            profiles: [ProfileConfig(id: "default", name: "Ana", dataDirPath: profile.path, isDefault: true)],
            nicknames: [:],
            processSnapshot: .empty
        )
        let slot1 = try XCTUnwrap(slots.first { $0.accountUuid == acc1 })
        let slot2 = try XCTUnwrap(slots.first { $0.accountUuid == acc2 })

        let engine = SessionSyncEngine(backupRootDir: tempRoot.appendingPathComponent("backups"))
        let summary = try engine.syncAllActive(from: slot1, to: slot2, bidirectional: true)

        XCTAssertEqual(summary.copiedCount, 1)  // local_a -> acc2
        XCTAssertEqual(summary.updatedCount, 1) // local_b acc2 -> acc1
        XCTAssertTrue(summary.errors.isEmpty)

        // Verify local_a copied to acc2
        XCTAssertTrue(fm.fileExists(atPath: dir2.appendingPathComponent("local_a.json").path))
        // Verify local_c NOT copied
        XCTAssertFalse(fm.fileExists(atPath: dir2.appendingPathComponent("local_c.json").path))
        // Verify local_b in acc1 now has 20 turns (never overwritten with 10!)
        let b1Data = try Data(contentsOf: dir1.appendingPathComponent("local_b.json"))
        let b1Obj = try XCTUnwrap(JSONSerialization.jsonObject(with: b1Data) as? [String: Any])
        XCTAssertEqual(b1Obj["completedTurns"] as? Int, 20)
    }

    func testInitializeSecondaryProfileCopiesOnlyMcpConfig() throws {
        let fm = FileManager.default
        let src = tempRoot.appendingPathComponent("SrcProfile", isDirectory: true)
        let dst = tempRoot.appendingPathComponent("DstProfile", isDirectory: true)
        try fm.createDirectory(at: src, withIntermediateDirectories: true)
        try Data(#"{"mcpServers":{"demo":{}}}"#.utf8).write(to: src.appendingPathComponent("claude_desktop_config.json"))
        try Data("SECRET_COOKIE".utf8).write(to: src.appendingPathComponent("Cookies"))

        let engine = SessionSyncEngine(backupRootDir: tempRoot.appendingPathComponent("backups"))
        let copied = try engine.initializeSecondaryProfile(at: dst, copyMcpConfigFrom: src)

        XCTAssertTrue(copied)
        XCTAssertTrue(fm.fileExists(atPath: dst.appendingPathComponent("claude_desktop_config.json").path))
        XCTAssertFalse(fm.fileExists(atPath: dst.appendingPathComponent("Cookies").path))
    }

    func testLaunchAgentToggleCreatesAndRemovesPlist() throws {
        let plist = tempRoot.appendingPathComponent("com.claudesync.app.plist")
        let mgr = LaunchAgentManager(plistURL: plist)

        XCTAssertFalse(mgr.isEnabled)
        try mgr.setEnabled(true, executablePath: "/Applications/ClaudeSYNC.app/Contents/MacOS/ClaudeSYNC")
        XCTAssertTrue(mgr.isEnabled)

        let data = try Data(contentsOf: plist)
        let obj = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(obj?["Label"] as? String, LaunchAgentManager.label)
        XCTAssertEqual(obj?["RunAtLoad"] as? Bool, true)

        try mgr.setEnabled(false)
        XCTAssertFalse(mgr.isEnabled)
    }

    // MARK: - Rate Limit Watcher & Auto-Switch Tests

    func testRateLimitWatcherParsesQuotaLimitsAndResetsAtFromTail() throws {
        let jsonl = tempRoot.appendingPathComponent("session.jsonl")
        let futureReset = Int(Date().timeIntervalSince1970) + 7200
        let isoNow = ISO8601DateFormatter().string(from: Date())
        let line = """
        {"type":"assistant","timestamp":"\(isoNow)","apiError":"usage_limit_reached","apiErrorStatus":429,"quotaLimits":{"status":"rejected","resetsAt":\(futureReset),"rateLimitType":"seven_day"}}
        """
        let content = "{\"type\":\"user\",\"text\":\"hello\"}\n" + line + "\n"
        try Data(content.utf8).write(to: jsonl)

        let watcher = RateLimitWatcher()
        let event = try XCTUnwrap(watcher.parseTailForRateLimit(fileURL: jsonl, cliSessionId: "cli-123"))
        XCTAssertEqual(event.rateLimitType, "seven_day")
        XCTAssertEqual(event.status, "rejected")
        XCTAssertTrue(event.isCurrentlyRejected)
        XCTAssertEqual(Int(event.resetsAt?.timeIntervalSince1970 ?? 0), futureReset)
    }

    func testAutoSwitchTriggersOnFresh429AndDeduplicatesEventKey() {
        let now = Date()
        let hit = RateLimitEvent(
            timestamp: now.addingTimeInterval(-30),
            rateLimitType: "five_hour",
            resetsAt: now.addingTimeInterval(3600),
            status: "rejected",
            cliSessionId: "cli-live"
        )
        let liveCard = ClaudeSessionCard(
            sessionId: "local_1",
            cliSessionId: "cli-live",
            title: "Canlı Görev",
            cwd: "/tmp/app",
            model: "claude-opus-5-5",
            completedTurns: 25,
            createdAt: now,
            lastActivityAt: now,
            lastFocusedAt: now,
            isArchived: false,
            filePath: tempRoot.appendingPathComponent("local_1.json"),
            fileModDate: now,
            transcriptPath: nil,
            transcriptSizeBytes: 1024,
            isLiveRunning: true
        )

        let acc1 = AccountSlot(
            profileId: "default",
            profileName: "Ana Profil",
            profileDataDir: tempRoot.appendingPathComponent("Claude"),
            isDefaultProfile: true,
            accountUuid: "11111111-1111-1111-1111-111111111111",
            orgUuid: "22222222-2222-2222-2222-222222222222",
            sessionsDir: tempRoot.appendingPathComponent("Claude/s1"),
            displayName: "Ultra 1",
            sessions: [liveCard],
            archivedIds: [],
            usage: OrgUsage(
                orgUuid: "22222222-2222-2222-2222-222222222222",
                fiveHourPercent: 100,
                sevenDayPercent: 45,
                extraUsagePercent: 0,
                updatedAt: now,
                history: [],
                lastRateLimitHit: hit
            ),
            isActiveAccount: true,
            runningPid: 101
        )
        let acc2 = AccountSlot(
            profileId: "secondary",
            profileName: "2. Profil",
            profileDataDir: tempRoot.appendingPathComponent("Claude-Account2"),
            isDefaultProfile: false,
            accountUuid: "33333333-3333-3333-3333-333333333333",
            orgUuid: "44444444-4444-4444-4444-444444444444",
            sessionsDir: tempRoot.appendingPathComponent("Claude-Account2/s2"),
            displayName: "Ultra 2",
            sessions: [],
            archivedIds: [],
            usage: OrgUsage(
                orgUuid: "44444444-4444-4444-4444-444444444444",
                fiveHourPercent: 0,
                sevenDayPercent: 6,
                extraUsagePercent: nil,
                updatedAt: now
            ),
            isActiveAccount: false,
            runningPid: nil
        )

        let watcher = RateLimitWatcher()
        let settings = BridgeSettings(autoSwitchEnabled: true, autoSwitchTrigger: .onRateLimitError)

        let decision = watcher.evaluateAutoSwitch(
            accounts: [acc1, acc2],
            settings: settings,
            lastHandledEventKey: nil,
            now: now
        )
        XCTAssertNotNil(decision)
        XCTAssertEqual(decision?.target.displayName, "Ultra 2")
        XCTAssertEqual(decision?.sessionsToTransfer.map(\.sessionId), ["local_1"])
        XCTAssertEqual(decision?.isZeroLogoutReady, true)

        // Same eventKey must NOT re-trigger
        let second = watcher.evaluateAutoSwitch(
            accounts: [acc1, acc2],
            settings: settings,
            lastHandledEventKey: decision?.eventKey,
            now: now
        )
        XCTAssertNil(second)
    }

    func testDiscoveryDeduplicatesInactiveAccountWhenDedicatedSecondaryProfileExists() throws {
        let fm = FileManager.default
        let p1 = tempRoot.appendingPathComponent("Claude", isDirectory: true)
        let p2 = tempRoot.appendingPathComponent("Claude-Account2", isDirectory: true)

        let acc1 = "11111111-1111-1111-1111-111111111111"
        let org1 = "22222222-2222-2222-2222-222222222222"
        let acc2 = "33333333-3333-3333-3333-333333333333"
        let org2 = "44444444-4444-4444-4444-444444444444"

        let p1Acc1 = p1.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let p1Acc2Old = p1.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        let p2Acc2Live = p2.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        for d in [p1Acc1, p1Acc2Old, p2Acc2Live] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }

        try writeSessionJSON(in: p1Acc1, sessionId: "local_1", cliSessionId: "c1", title: "A1", cwd: "/tmp", turns: 5, lastActivityMs: 2000)
        try writeSessionJSON(in: p1Acc2Old, sessionId: "local_2", cliSessionId: "c2", title: "Old A2", cwd: "/tmp", turns: 3, lastActivityMs: 1000)
        try writeSessionJSON(in: p2Acc2Live, sessionId: "local_2", cliSessionId: "c2", title: "New A2", cwd: "/tmp", turns: 4, lastActivityMs: 1500)

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("projects"))
        let slots = discovery.discoverAccounts(
            profiles: [
                ProfileConfig(id: "default", name: "Ana", dataDirPath: p1.path, isDefault: true),
                ProfileConfig(id: "p2", name: "2. Profil", dataDirPath: p2.path, isDefault: false)
            ],
            nicknames: [:],
            processSnapshot: ProcessSnapshot(
                runningInstances: [],
                liveCliSessionIds: [],
                activeAccountOrgPairs: ["\(acc1)/\(org1)"]
            )
        )

        // Should show 2 accounts cleanly (acc1 in p1, acc2 in p2), hiding stale inactive acc2 in p1
        XCTAssertEqual(slots.count, 2)
        let slot2 = try XCTUnwrap(slots.first { $0.accountUuid == acc2 })
        XCTAssertFalse(slot2.isDefaultProfile)
        XCTAssertEqual(slot2.sessions.first?.title, "New A2")
    }

    func testAutoSyncSharedCardsUpdatesOnlySharedSessionsAndSkipsUnshared() throws {
        let fm = FileManager.default
        let p1 = tempRoot.appendingPathComponent("P1", isDirectory: true)
        let p2 = tempRoot.appendingPathComponent("P2", isDirectory: true)
        let acc1 = "11111111-1111-1111-1111-111111111111"
        let org1 = "22222222-2222-2222-2222-222222222222"
        let acc2 = "33333333-3333-3333-3333-333333333333"
        let org2 = "44444444-4444-4444-4444-444444444444"

        let dir1 = p1.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let dir2 = p2.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir2, withIntermediateDirectories: true)

        // Shared session X: Account 2 worked 15 more turns (25 vs 10) -> should auto-update Account 1!
        try writeSessionJSON(in: dir1, sessionId: "local_x", cliSessionId: "cli-x", title: "Session X", cwd: "/tmp", turns: 10, lastActivityMs: 1000)
        try writeSessionJSON(in: dir2, sessionId: "local_x", cliSessionId: "cli-x", title: "Session X (Updated)", cwd: "/tmp", turns: 25, lastActivityMs: 5000)

        // Unshared session Y: exists ONLY in Account 2 -> must NOT be auto-copied to Account 1!
        try writeSessionJSON(in: dir2, sessionId: "local_y", cliSessionId: "cli-y", title: "Private Y", cwd: "/tmp", turns: 8, lastActivityMs: 5000)

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("projects"))
        let slots = discovery.discoverAccounts(
            profiles: [
                ProfileConfig(id: "p1", name: "P1", dataDirPath: p1.path, isDefault: true),
                ProfileConfig(id: "p2", name: "P2", dataDirPath: p2.path, isDefault: false)
            ],
            nicknames: [:],
            processSnapshot: .empty
        )
        let slot1 = try XCTUnwrap(slots.first { $0.accountUuid == acc1 })
        let slot2 = try XCTUnwrap(slots.first { $0.accountUuid == acc2 })

        let engine = SessionSyncEngine(backupRootDir: tempRoot.appendingPathComponent("backups"))
        let summary = try engine.syncSharedCards(between: slot1, and: slot2)

        XCTAssertEqual(summary.updatedCount, 1)
        XCTAssertEqual(summary.syncedTitles, ["Session X (Updated)"])

        // Account 1's local_x must now have 25 turns and updated title
        let x1Data = try Data(contentsOf: dir1.appendingPathComponent("local_x.json"))
        let x1Obj = try XCTUnwrap(JSONSerialization.jsonObject(with: x1Data) as? [String: Any])
        XCTAssertEqual(x1Obj["completedTurns"] as? Int, 25)
        XCTAssertEqual(x1Obj["title"] as? String, "Session X (Updated)")

        // Unshared local_y must NOT exist in Account 1
        XCTAssertFalse(fm.fileExists(atPath: dir1.appendingPathComponent("local_y.json").path))

        // Running a second time after rediscovery must perform 0 writes (idempotent!)
        let slotsAfter = discovery.discoverAccounts(
            profiles: [
                ProfileConfig(id: "p1", name: "P1", dataDirPath: p1.path, isDefault: true),
                ProfileConfig(id: "p2", name: "P2", dataDirPath: p2.path, isDefault: false)
            ],
            nicknames: [:],
            processSnapshot: .empty
        )
        let s1After = try XCTUnwrap(slotsAfter.first { $0.accountUuid == acc1 })
        let s2After = try XCTUnwrap(slotsAfter.first { $0.accountUuid == acc2 })
        let secondSummary = try engine.syncSharedCards(between: s1After, and: s2After)
        XCTAssertEqual(secondSummary.updatedCount, 0)
    }

    func testBilingualLocalizationAndOnboardingSettingsPersistence() throws {
        // Default settings should require onboarding, default to single-window mode, & support system language
        let fresh = BridgeSettings()
        XCTAssertFalse(fresh.hasCompletedOnboarding)
        XCTAssertEqual(fresh.language, .system)
        XCTAssertTrue(fresh.singleWindowMode)

        // Encode/decode roundtrip preserving language, onboarding & singleWindowMode flag
        var custom = BridgeSettings(language: .english, hasCompletedOnboarding: true, singleWindowMode: false)
        let encoded = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(BridgeSettings.self, from: encoded)
        XCTAssertEqual(decoded.language, .english)
        XCTAssertTrue(decoded.hasCompletedOnboarding)
        XCTAssertFalse(decoded.singleWindowMode)
        XCTAssertFalse(decoded.language.resolvedIsTurkish)

        custom.language = .turkish
        XCTAssertTrue(custom.language.resolvedIsTurkish)

        // Localized date formatters produce distinct native TR vs EN strings
        let now = Date()
        XCTAssertEqual(LocalizedDateFormatter.relativeString(from: now.addingTimeInterval(-120), now: now, isTurkish: true), "2 dk önce")
        XCTAssertEqual(LocalizedDateFormatter.relativeString(from: now.addingTimeInterval(-120), now: now, isTurkish: false), "2m ago")
        XCTAssertEqual(LocalizedDateFormatter.countdownString(until: now.addingTimeInterval(3600 * 50), now: now, isTurkish: true), "2g 2sa kaldı")
        XCTAssertEqual(LocalizedDateFormatter.countdownString(until: now.addingTimeInterval(3600 * 50), now: now, isTurkish: false), "2d 2h left")

        // Localized profile names
        XCTAssertEqual(ProfileConfig.defaultProfile.localizedName(isTurkish: true), "Ana Profil")
        XCTAssertEqual(ProfileConfig.defaultProfile.localizedName(isTurkish: false), "Primary Profile")
        XCTAssertEqual(MenuBarDisplayMode.iconAndActiveUsage.title(isTurkish: false), "Active 5h/7d")
        XCTAssertEqual(MenuBarDisplayMode.iconAndActiveUsage.title(isTurkish: true), "Aktif 5s/7g")
    }

    func testSingleWindowDiscoveryMarksOnlyRunningProfileActive() throws {
        let fm = FileManager.default
        let p1 = tempRoot.appendingPathComponent("Claude", isDirectory: true)
        let p2 = tempRoot.appendingPathComponent("Claude-Account2", isDirectory: true)

        let acc1 = "11111111-1111-4000-8000-000000000001"
        let org1 = "22222222-2222-4000-8000-000000000001"
        let acc2 = "33333333-3333-4000-8000-000000000002"
        let org2 = "44444444-4444-4000-8000-000000000002"

        let dir1 = p1.appendingPathComponent("claude-code-sessions/\(acc1)/\(org1)", isDirectory: true)
        let dir2 = p2.appendingPathComponent("claude-code-sessions/\(acc2)/\(org2)", isDirectory: true)
        try fm.createDirectory(at: dir1, withIntermediateDirectories: true)
        try fm.createDirectory(at: dir2, withIntermediateDirectories: true)

        try writeSessionJSON(in: dir1, sessionId: "local_1", cliSessionId: "cli-1", title: "P1", cwd: "/tmp", turns: 10, lastActivityMs: 1_795_000_000_000)
        try writeSessionJSON(in: dir2, sessionId: "local_2", cliSessionId: "cli-2", title: "P2", cwd: "/tmp", turns: 5, lastActivityMs: 1_794_000_000_000)

        // Only Profile 2 is running (Single-Window Mode after switching!)
        let snap = ProcessSnapshot(
            runningInstances: [
                RunningClaudeInstance(pid: 7777, dataDir: p2.standardizedFileURL.path, isDefaultProfile: false)
            ],
            liveCliSessionIds: [],
            activeAccountOrgPairs: []
        )

        let discovery = SessionDiscovery(claudeProjectsDir: tempRoot.appendingPathComponent("empty"))
        let slots = discovery.discoverAccounts(
            profiles: [
                ProfileConfig(id: "default", name: "Ana Profil", dataDirPath: p1.path, isDefault: true),
                ProfileConfig(id: "secondary-account-2", name: "2. Profil", dataDirPath: p2.path, isDefault: false)
            ],
            nicknames: [:],
            processSnapshot: snap
        )

        XCTAssertEqual(slots.count, 2)
        let slot1 = try XCTUnwrap(slots.first { $0.accountUuid == acc1 })
        let slot2 = try XCTUnwrap(slots.first { $0.accountUuid == acc2 })
        XCTAssertFalse(slot1.isActiveAccount)
        XCTAssertTrue(slot2.isActiveAccount)
        XCTAssertEqual(slot2.runningPid, 7777)
        XCTAssertNil(slot1.runningPid)
    }

    // MARK: - Helper

    private func writeSessionJSON(
        in dir: URL,
        sessionId: String,
        cliSessionId: String,
        title: String,
        cwd: String,
        turns: Int,
        lastActivityMs: Int64,
        isArchived: Bool = false
    ) throws {
        let obj: [String: Any] = [
            "sessionId": sessionId,
            "cliSessionId": cliSessionId,
            "title": title,
            "cwd": cwd,
            "completedTurns": turns,
            "lastActivityAt": lastActivityMs,
            "lastFocusedAt": lastActivityMs,
            "isArchived": isArchived
        ]
        let data = try JSONSerialization.data(withJSONObject: obj)
        try data.write(to: dir.appendingPathComponent("\(sessionId).json"))
    }
}
