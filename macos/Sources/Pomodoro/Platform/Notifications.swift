import Foundation
import UserNotifications
import AppKit

/// Phase alarms and the Whistler reminder, delivered through Notification
/// Center. Actionable buttons are the native equivalent of the tray balloon
/// the Windows build shows.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    private var authorized = false
    /// Falls back to NSAlert-free logging when notifications are unavailable,
    /// which is the case for an unsigned bundle run straight from the build.
    private var center: UNUserNotificationCenter? {
        guard Bundle.main.bundleIdentifier != nil else { return nil }
        return UNUserNotificationCenter.current()
    }

    var onSkip: (() -> Void)?

    func configure() {
        guard let center else { return }
        center.delegate = self
        let skip = UNNotificationAction(identifier: "skip", title: "Start next phase", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "phase", actions: [skip],
                                   intentIdentifiers: [], options: [])
        ])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            DispatchQueue.main.async { self?.authorized = granted }
        }
    }

    func post(title: String, body: String, category: String? = nil) {
        guard let center else {
            NSLog("pomodoro: %@ — %@", title, body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = nil // the alarm is played separately so it works unsigned
        if let category { content.categoryIdentifier = category }
        center.add(UNNotificationRequest(identifier: UUID().uuidString,
                                         content: content,
                                         trigger: nil))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler handler: @escaping (UNNotificationPresentationOptions) -> Void) {
        handler([.banner, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler handler: @escaping () -> Void) {
        if response.actionIdentifier == "skip" {
            DispatchQueue.main.async { [weak self] in self?.onSkip?() }
        }
        handler()
    }
}
