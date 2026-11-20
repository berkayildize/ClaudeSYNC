import AppKit
import Foundation

public enum ProcessMonitorError: LocalizedError {
    case claudeAppNotFound
    case failedToLaunch(String)
    case gracefulQuitTimedOut

    public var errorDescription: String? {
        switch self {
        case .claudeAppNotFound:
            return "/Applications/Claude.app bulunamadı."
        case .failedToLaunch(let msg):
            return "Claude Desktop başlatılamadı: \(msg)"
        case .gracefulQuitTimedOut:
            return "Claude Desktop 6 saniye içinde kapanmadı. Açık bir onay penceresi olabilir."
        }
    }
}

public struct ProcessMonitor: Sendable {
    public static let claudeAppPath = "/Applications/Claude.app"

    public init() {}

    public func captureSnapshot() -> ProcessSnapshot {
        let defaultDir = ProfileConfig.defaultProfile.expandedURL.standardizedFileURL.path
        guard let output = runCommand("/bin/ps", arguments: ["-eo", "pid,args"]) else {
            return .empty
        }
        return Self.parsePsOutput(output, defaultDataDir: defaultDir)
    }

    public static func parsePsOutput(_ raw: String, defaultDataDir: String) -> ProcessSnapshot {
        var instances: [RunningClaudeInstance] = []
        var liveSessions = Set<String>()
        var activePairs = Set<String>()

        let resumeRegex = try? NSRegularExpression(
            pattern: #"--resume(?:=|\s+)([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#
        )
        let agentPairRegex = try? NSRegularExpression(
            pattern: #"local-agent-mode-sessions/([0-9a-fA-F-]{36})/([0-9a-fA-F-]{36})/"#
        )

        for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let firstSpace = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else { continue }
            let pidStr = String(line[..<firstSpace])
            guard let pid = Int32(pidStr) else { continue }
            let args = String(line[firstSpace...]).trimmingCharacters(in: .whitespaces)

            // 1. Main Claude Desktop process (exclude Helpers/Renderer/GPU/etc.)
            if args.hasPrefix("/Applications/Claude.app/Contents/MacOS/Claude") {
                let tail = args.dropFirst("/Applications/Claude.app/Contents/MacOS/Claude".count)
                if tail.isEmpty || tail.first == " " {
                    if let customDir = extractUserDataDir(from: args) {
                        let stdCustom = URL(fileURLWithPath: (customDir as NSString).expandingTildeInPath)
                            .standardizedFileURL.path
                        let isDef = (stdCustom == defaultDataDir)
                        instances.append(RunningClaudeInstance(pid: pid, dataDir: stdCustom, isDefaultProfile: isDef))
                    } else {
                        instances.append(RunningClaudeInstance(pid: pid, dataDir: defaultDataDir, isDefaultProfile: true))
                    }
                }
            }

            // 2. Live Claude Code CLI worker (--resume=<uuid>)
            if args.contains("claude") && args.contains("--resume") {
                let nsArgs = args as NSString
                let range = NSRange(location: 0, length: nsArgs.length)
                if let matches = resumeRegex?.matches(in: args, range: range) {
                    for match in matches where match.numberOfRanges > 1 {
                        let uuid = nsArgs.substring(with: match.range(at: 1)).lowercased()
                        liveSessions.insert(uuid)
                    }
                }
            }

            // 3. Active account/org from running local-agent-mode-sessions workers
            if args.contains("local-agent-mode-sessions/") {
                let nsArgs = args as NSString
                let range = NSRange(location: 0, length: nsArgs.length)
                if let matches = agentPairRegex?.matches(in: args, range: range) {
                    for match in matches where match.numberOfRanges > 2 {
                        let acc = nsArgs.substring(with: match.range(at: 1)).lowercased()
                        let org = nsArgs.substring(with: match.range(at: 2)).lowercased()
                        activePairs.insert("\(acc)/\(org)")
                    }
                }
            }
        }

        return ProcessSnapshot(
            runningInstances: instances,
            liveCliSessionIds: liveSessions,
            activeAccountOrgPairs: activePairs
        )
    }

    public static func extractUserDataDir(from args: String) -> String? {
        guard let markerRange = args.range(of: "--user-data-dir=") else { return nil }
        let after = String(args[markerRange.upperBound...])
        // Stop at the next " --" flag if any, preserving spaces inside path
        let rawValue: String
        if let nextFlag = after.range(of: " --") {
            rawValue = String(after[..<nextFlag.lowerBound])
        } else {
            rawValue = after
        }
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("'") && trimmed.hasSuffix("'")) {
            trimmed = String(trimmed.dropFirst().dropLast())
        }
        return trimmed.isEmpty ? nil : trimmed
    }

    @MainActor
    public func activateInstance(pid: Int32) -> Bool {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate(options: [.activateAllWindows])
    }

    public func launchProfile(dataDir: URL, isDefault: Bool) throws {
        guard FileManager.default.fileExists(atPath: Self.claudeAppPath) else {
            throw ProcessMonitorError.claudeAppNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if isDefault {
            process.arguments = ["-a", Self.claudeAppPath]
        } else {
            process.arguments = [
                "-n",
                "-a", Self.claudeAppPath,
                "--args",
                "--user-data-dir=\(dataDir.standardizedFileURL.path)"
            ]
        }

        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ProcessMonitorError.failedToLaunch(errText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    public func gracefulRestart(pid: Int32?, dataDir: URL, isDefault: Bool) async throws {
        if let pid {
            let terminated: Bool = await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: pid) else { return true }
                app.terminate()
                return false
            }

            if !terminated {
                // Poll cleanly up to 6 seconds (every 150ms) for graceful shutdown
                var exited = false
                for _ in 0..<40 {
                    try await Task.sleep(nanoseconds: 150_000_000)
                    let stillAlive: Bool = await MainActor.run {
                        NSRunningApplication(processIdentifier: pid) != nil
                    }
                    if !stillAlive {
                        exited = true
                        break
                    }
                }
                if !exited {
                    throw ProcessMonitorError.gracefulQuitTimedOut
                }
            }
            // Brief settle pause so Electron releases locks cleanly
            try await Task.sleep(nanoseconds: 350_000_000)
        }

        try launchProfile(dataDir: dataDir, isDefault: isDefault)
    }

    private func runCommand(_ path: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()

        do {
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
