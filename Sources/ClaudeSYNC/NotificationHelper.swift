import AppKit
import Foundation
import UserNotifications

enum NotificationPermissionState: Equatable {
    case authorized
    case notDetermined
    case denied
    case unavailable
}

@MainActor
final class NotificationHelper {
    static let shared = NotificationHelper()
    private var requestedAuth = false

    private var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    func authorizationState() async -> NotificationPermissionState {
        guard isBundledApp else { return .unavailable }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return .authorized
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .notDetermined
        }
    }

    @discardableResult
    func requestPermissionExplicitly() async -> NotificationPermissionState {
        guard isBundledApp else { return .unavailable }
        requestedAuth = true
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            return granted ? .authorized : await authorizationState()
        } catch {
            return await authorizationState()
        }
    }

    func requestPermissionIfNeeded() {
        guard isBundledApp, !requestedAuth else { return }
        requestedAuth = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func openSystemNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
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
