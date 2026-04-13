import Foundation
import UserNotifications

protocol AskCompletionNotifying {
    func notifyAskFinished(taskTitle: String, workspacePath: String, hadError: Bool)
}

final class AskCompletionNotificationService: AskCompletionNotifying {
    static let shared = AskCompletionNotificationService()

    private init() {}

    func notifyAskFinished(taskTitle: String, workspacePath: String, hadError: Bool) {
        guard notificationsEnabled else { return }

        let title = Self.notificationTitle(from: taskTitle, hadError: hadError)
        let body = Self.notificationBody(workspacePath: workspacePath, hadError: hadError)
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                self.enqueueNotification(center: center, title: title, body: body, workspacePath: workspacePath)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    guard granted else { return }
                    self.enqueueNotification(center: center, title: title, body: body, workspacePath: workspacePath)
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private func enqueueNotification(
        center: UNUserNotificationCenter,
        title: String,
        body: String,
        workspacePath: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "ask-finished-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request)
    }

    private static func notificationTitle(from taskTitle: String, hadError: Bool) -> String {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return hadError ? "Ask failed" : "Ask finished"
    }

    private static func notificationBody(workspacePath: String, hadError: Bool) -> String {
        let workspaceName = workspaceDisplayName(for: workspacePath)
        let status = hadError ? "failed" : "finished"
        if workspaceName.isEmpty {
            return "Cursor Metro ask \(status)."
        }
        return "Cursor Metro ask \(status) in \(workspaceName)."
    }

    private static func workspaceDisplayName(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if expanded == homePath {
            return "~/"
        }
        let url = URL(fileURLWithPath: expanded)
        let name = url.lastPathComponent
        if !name.isEmpty {
            return name
        }
        return url.deletingLastPathComponent().lastPathComponent
    }

    private var notificationsEnabled: Bool {
        UserDefaults.standard.object(forKey: AppPreferences.askCompletionNotificationsEnabledKey) as? Bool
            ?? AppPreferences.defaultAskCompletionNotificationsEnabled
    }
}
