import Foundation

public struct LaunchAgentManager: Sendable {
    public static let label = "com.claudesync.app"

    public let plistURL: URL

    public init(plistURL: URL = Self.defaultPlistURL) {
        self.plistURL = plistURL
    }

    public static var defaultPlistURL: URL {
        URL(
            fileURLWithPath: ("~/Library/LaunchAgents/\(label).plist" as NSString).expandingTildeInPath
        )
    }

    public var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public func setEnabled(_ enabled: Bool, executablePath: String? = Bundle.main.executablePath) throws {
        let fm = FileManager.default

        if enabled {
            guard let execPath = executablePath, !execPath.isEmpty else { return }
            try fm.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let plistDict: [String: Any] = [
                "Label": Self.label,
                "ProgramArguments": [execPath],
                "RunAtLoad": true,
                "KeepAlive": false,
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(
                fromPropertyList: plistDict,
                format: .xml,
                options: 0
            )
            try data.write(to: plistURL, options: .atomic)
        } else {
            if fm.fileExists(atPath: plistURL.path) {
                try fm.removeItem(at: plistURL)
            }
        }
    }
}
