import Foundation
import UserNotifications

/// A nudge to write feedback every few days at a chosen time. The next
/// occurrences are queued with Notification Center ahead of time, so they
/// arrive while the app is closed; launching or changing the setting
/// re-queues them from the day the reminder was turned on.
@MainActor
final class FeedbackReminder: ObservableObject {
    static let shared = FeedbackReminder()
    static let prefix = "feedback-reminder-"
    private static let queued = 8

    private let defaults = UserDefaults.standard

    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "feedbackReminderEnabled")
            if enabled && !oldValue { anchor = Date() }
            schedule()
        }
    }
    @Published var everyDays: Int { didSet { defaults.set(everyDays, forKey: "feedbackReminderDays"); schedule() } }
    @Published var time: Date { didSet { defaults.set(time.timeIntervalSince1970, forKey: "feedbackReminderTime"); schedule() } }

    /// The day counting starts from, so "every 3 days" keeps its rhythm across launches.
    private var anchor: Date {
        get { (defaults.object(forKey: "feedbackReminderAnchor") as? Double).map(Date.init(timeIntervalSince1970:)) ?? Date() }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: "feedbackReminderAnchor") }
    }

    private init() {
        enabled = defaults.bool(forKey: "feedbackReminderEnabled")
        let days = defaults.integer(forKey: "feedbackReminderDays")
        everyDays = days >= 1 ? min(days, 30) : 7
        let stored = defaults.double(forKey: "feedbackReminderTime")
        time = stored > 0 ? Date(timeIntervalSince1970: stored)
            : Calendar.current.date(bySettingHour: 16, minute: 0, second: 0, of: Date()) ?? Date()
    }

    func occurrences(after now: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        guard var next = calendar.date(bySettingHour: clock.hour ?? 16, minute: clock.minute ?? 0, second: 0,
                                       of: calendar.startOfDay(for: anchor)) else { return [] }
        var dates: [Date] = []
        while dates.count < Self.queued {
            if next > now { dates.append(next) }
            guard let later = calendar.date(byAdding: .day, value: everyDays, to: next) else { break }
            next = later
        }
        return dates
    }

    func schedule() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let identifiers = (0..<Self.queued).map { Self.prefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard enabled else { return }
        for (index, date) in occurrences().enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "Write feedback"
            content.body = "Jot down what your team did lately. It takes a minute."
            content.sound = .default
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            center.add(UNNotificationRequest(identifier: identifiers[index], content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)))
        }
    }
}
