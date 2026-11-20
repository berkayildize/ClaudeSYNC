import Foundation
import UserNotifications

@MainActor
final class NotificationHelper {
    static let shared = NotificationHelper()
    private var requestedAuth = false

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func requestPermissionIfNeeded() {
        guard isBundledApp, !requestedAuth else { return }
        requestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func send(title: String, body: String) {
        guard isBundledApp else { return }
        requestPermissionIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(
            identifier: "csb-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }
}
