import Foundation

/// Date and duration helpers ported from `Service.qml`. Every calculation is
/// local-calendar based, exactly as the QML `Date` methods were, so day keys
/// written by either front end agree.
enum Fmt {
    static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        return cal
    }()

    static func pad(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }

    /// Clock display for the timer. Negative values render with a leading "-"
    /// so overtime reads naturally.
    static func duration(_ value: Int) -> String {
        let sign = value < 0 ? "-" : ""
        let seconds = abs(value)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 {
            return "\(sign)\(hours):\(pad(minutes)):\(pad(remainder))"
        }
        return "\(sign)\(pad(minutes)):\(pad(remainder))"
    }

    /// Human-readable duration used by reports, e.g. "1h 25m".
    static func reportDuration(_ seconds: Double) -> String {
        let minutes = max(0, Int((seconds / 60).rounded()))
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder > 0 ? "\(hours)h \(remainder)m" : "\(hours)h"
    }

    static func reportDuration(_ seconds: Int) -> String { reportDuration(Double(seconds)) }

    /// Minutes as reported by the Whistler bridge.
    static func whistlerMinutes(_ minutes: Double) -> String {
        reportDuration(max(0, minutes) * 60)
    }

    static func whistlerSignedMinutes(_ minutes: Double) -> String {
        let magnitude = reportDuration(abs(minutes) * 60)
        if minutes > 0 { return "+\(magnitude)" }
        if minutes < 0 { return "-\(magnitude)" }
        return magnitude
    }

    /// Minute-of-day to a wall clock label, with 1440 shown as 24:00.
    static func whistlerClock(_ value: Double) -> String {
        let total = max(0, min(1440, Int(value.rounded())))
        if total == 1440 { return "24:00" }
        return "\(pad(total / 60)):\(pad(total % 60))"
    }

    // MARK: - Day keys

    static func date(from millis: EpochMillis) -> Date? {
        guard millis.isFinite else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }

    static func dateKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "" }
        return "\(y)-\(pad(m))-\(pad(d))"
    }

    static func dateKey(_ millis: EpochMillis) -> String {
        guard let date = date(from: millis) else { return "" }
        return dateKey(date)
    }

    /// Local midnight for a `YYYY-MM-DD` key, or nil when malformed.
    static func dayStart(forKey key: String) -> Date? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              m >= 1, m <= 12, d >= 1, d <= 31 else { return nil }
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        return calendar.date(from: components)
    }

    static func dayStartMillis(forKey key: String) -> EpochMillis? {
        guard let date = dayStart(forKey: key) else { return nil }
        return date.timeIntervalSince1970 * 1000
    }

    /// Absolute day index used for streak arithmetic, matching the QML
    /// `dayOrdinal` (UTC midnight divided by one day).
    static func dayOrdinal(_ key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        guard let date = utc.date(from: components) else { return nil }
        return Int(floor(date.timeIntervalSince1970 / 86400))
    }

    // MARK: - Labels

    static let shortMonths = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
                              "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    static let longMonths = ["January", "February", "March", "April", "May", "June",
                             "July", "August", "September", "October", "November", "December"]
    static let longWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday",
                               "Thursday", "Friday", "Saturday"]

    static func shortDateLabel(_ date: Date) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        guard let m = c.month, let d = c.day else { return "" }
        return "\(shortMonths[m - 1]) \(d)"
    }

    static func dayLabel(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let y = c.year, let m = c.month, let d = c.day, let w = c.weekday else { return "" }
        return "\(longWeekdays[w - 1]), \(longMonths[m - 1]) \(d), \(y)"
    }

    static func monthKey(year: Int, month: Int) -> String { "\(year)-\(pad(month + 1))" }
    static func monthLabel(year: Int, month: Int) -> String { "\(longMonths[month]) \(year)" }
    static func monthShortLabel(year: Int, month: Int) -> String {
        "\(shortMonths[month]) \(String(year).suffix(2))"
    }

    static func monthParts(_ key: String) -> (year: Int, month: Int)? {
        let parts = key.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]),
              m >= 1, m <= 12 else { return nil }
        return (y, m - 1)
    }

    static func timeLabel(_ millis: EpochMillis) -> String {
        guard let date = date(from: millis) else { return "--:--" }
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return "\(pad(c.hour ?? 0)):\(pad(c.minute ?? 0))"
    }

    static func rangeLabel(_ entry: SessionEntry) -> String {
        "\(timeLabel(entry.startedAt))–\(timeLabel(entry.endedAt))"
    }

    /// Monday-first weekday index, matching `(getDay() + 6) % 7` in QML.
    static func mondayFirstIndex(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date) - 1
        return (weekday + 6) % 7
    }
}
