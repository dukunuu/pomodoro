import Foundation

struct DayStats {
    var key = ""
    var sessions = 0
    var focusSeconds = 0
    var breakSeconds = 0
    var breaks = 0
    var completedBreaks = 0
    var shortBreaks = 0
    var longBreaks = 0
    var interruptedFocus = 0
    var interruptedBreaks = 0
    var phases = 0

    var totalSeconds: Int { focusSeconds + breakSeconds }
    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
    var totalText: String { Fmt.reportDuration(totalSeconds) }
}

struct WeekDay: Identifiable {
    var key: String
    var label: String
    var dayNumber: Int
    var isToday: Bool
    var sessions: Int
    var breaks: Int
    var focusSeconds: Int
    var breakSeconds: Int
    var id: String { key }

    var totalSeconds: Int { focusSeconds + breakSeconds }
    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
}

struct WeekReport {
    var startKey = ""
    var endKey = ""
    var startLabel = ""
    var endLabel = ""
    var days: [WeekDay] = []
    var sessions = 0
    var focusSeconds = 0
    var breakSeconds = 0
    var maxTotalSeconds = 0

    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
    var averageDayText: String { Fmt.reportDuration(Double(focusSeconds) / 7) }
}

struct MonthCell: Identifiable {
    var id: Int
    var inMonth: Bool
    var key: String = ""
    var dayNumber: Int = 0
    var isToday: Bool = false
    var focusSeconds: Int = 0
    var breakSeconds: Int = 0
    var sessions: Int = 0

    var focusText: String { Fmt.reportDuration(focusSeconds) }
}

struct MonthReport {
    var key = ""
    var label = ""
    var shortLabel = ""
    var cells: [MonthCell] = []
    var sessions = 0
    var focusSeconds = 0
    var breakSeconds = 0
    var activeDays = 0
    var maxDaySeconds = 0

    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
}

struct MonthBar: Identifiable {
    var key: String
    var label: String
    var focusSeconds: Int
    var breakSeconds: Int
    var sessions: Int
    var id: String { key }
    var totalSeconds: Int { focusSeconds + breakSeconds }
    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
}

struct AllTimeReport {
    var sessions = 0
    var focusSeconds = 0
    var breakSeconds = 0
    var breaks = 0
    var activeDays = 0
    var currentStreak = 0
    var longestStreak = 0
    var interrupted = 0
    var firstEndedAt: EpochMillis = 0
    var lastEndedAt: EpochMillis = 0
    var months: [MonthBar] = []
    var maxChartSeconds = 0

    var focusText: String { Fmt.reportDuration(focusSeconds) }
    var breakText: String { Fmt.reportDuration(breakSeconds) }
    var averageSessionText: String {
        sessions > 0 ? Fmt.reportDuration(Double(focusSeconds) / Double(sessions)) : "0m"
    }
}

/// Report aggregation, ported from `Service.qml`. Every figure here is derived
/// from `sessions`, so the three front ends report identical numbers from the
/// same history file.
extension PomodoroService {

    func statsForDay(_ key: String) -> DayStats {
        var stats = DayStats(key: key)
        for entry in sessions where Fmt.dateKey(entry.endedAt) == key {
            let active = entry.activeSeconds
            stats.phases += 1
            if entry.phase == .focus {
                stats.focusSeconds += active
                if entry.isCompletedFocus {
                    stats.sessions += 1
                } else if active > 0 {
                    stats.interruptedFocus += 1
                }
            } else {
                stats.breakSeconds += active
                if active > 0 { stats.breaks += 1 }
                if entry.status == .completed { stats.completedBreaks += 1 }
                if entry.phase == .short && active > 0 { stats.shortBreaks += 1 }
                if entry.phase == .long && active > 0 { stats.longBreaks += 1 }
                if entry.status != .completed && active > 0 { stats.interruptedBreaks += 1 }
            }
        }
        return stats
    }

    private func clippedSegments(_ segments: [Segment],
                                 from rangeStart: EpochMillis,
                                 to rangeEnd: EpochMillis) -> [Segment] {
        segments.compactMap { segment in
            let start = max(rangeStart, segment.startedAt)
            let end = min(rangeEnd, segment.endedAt)
            guard end > start else { return nil }
            return Segment(startedAt: start, endedAt: end)
        }
    }

    /// Every phase overlapping the day, including the one in progress, sorted
    /// by start. This is what the timeline and the session list read.
    func entriesForDay(_ key: String) -> [SessionEntry] {
        guard let dayStart = Fmt.dayStartMillis(forKey: key) else { return [] }
        let dayEnd = dayStart + 86_400_000
        var rows: [SessionEntry] = []

        for entry in sessions {
            guard entry.endedAt >= dayStart, entry.startedAt < dayEnd else { continue }
            var row = entry
            row.segments = clippedSegments(entry.segments, from: dayStart, to: dayEnd)
            rows.append(row)
        }

        if phaseStartedAt > 0 {
            let now = nowMillis()
            let activeEnd = max(now, phaseStartedAt)
            if activeEnd >= dayStart && phaseStartedAt < dayEnd {
                rows.append(SessionEntry(
                    id: "active-phase",
                    phase: phase,
                    status: running ? .running : .paused,
                    startedAt: phaseStartedAt,
                    endedAt: now,
                    plannedSeconds: phasePlannedSeconds > 0 ? phasePlannedSeconds : duration(for: phase),
                    activeSeconds: phaseElapsed(at: now),
                    segments: clippedSegments(phaseSegments(at: now), from: dayStart, to: dayEnd),
                    note: phase == .focus ? activeNote : "",
                    isLive: true
                ))
            }
        }

        rows.sort { $0.startedAt < $1.startedAt }
        return rows
    }

    /// Completed focus sessions for the day, newest first.
    func sessionsForDay(_ key: String, limit: Int? = nil) -> [SessionEntry] {
        var result: [SessionEntry] = []
        for entry in entriesForDay(key).reversed() where entry.isCompletedFocus {
            result.append(entry)
            if let limit, result.count >= limit { break }
        }
        return result
    }

    func weeklyStats(anchor: Date) -> WeekReport {
        let cal = Fmt.calendar
        let today = cal.startOfDay(for: anchor)
        let monday = cal.date(byAdding: .day, value: -Fmt.mondayFirstIndex(today), to: today) ?? today
        let names = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

        var report = WeekReport()
        for index in 0..<7 {
            guard let date = cal.date(byAdding: .day, value: index, to: monday) else { continue }
            let stats = statsForDay(Fmt.dateKey(date))
            report.days.append(WeekDay(
                key: stats.key,
                label: names[index],
                dayNumber: cal.component(.day, from: date),
                isToday: stats.key == todayKey,
                sessions: stats.sessions,
                breaks: stats.breaks,
                focusSeconds: stats.focusSeconds,
                breakSeconds: stats.breakSeconds
            ))
            report.sessions += stats.sessions
            report.focusSeconds += stats.focusSeconds
            report.breakSeconds += stats.breakSeconds
            report.maxTotalSeconds = max(report.maxTotalSeconds, stats.totalSeconds)
        }
        let sunday = cal.date(byAdding: .day, value: 6, to: monday) ?? monday
        report.startKey = Fmt.dateKey(monday)
        report.endKey = Fmt.dateKey(sunday)
        report.startLabel = Fmt.shortDateLabel(monday)
        report.endLabel = Fmt.shortDateLabel(sunday)
        return report
    }

    func monthlyStats(year: Int, month: Int) -> MonthReport {
        let cal = Fmt.calendar
        var components = DateComponents()
        components.year = year
        components.month = month + 1
        components.day = 1
        guard let first = cal.date(from: components),
              let range = cal.range(of: .day, in: .month, for: first) else { return MonthReport() }

        var report = MonthReport(
            key: Fmt.monthKey(year: year, month: month),
            label: Fmt.monthLabel(year: year, month: month),
            shortLabel: Fmt.monthShortLabel(year: year, month: month)
        )

        let leading = Fmt.mondayFirstIndex(first)
        for blank in 0..<leading {
            report.cells.append(MonthCell(id: blank, inMonth: false))
        }
        for dayNumber in range {
            guard let date = cal.date(byAdding: .day, value: dayNumber - 1, to: first) else { continue }
            let stats = statsForDay(Fmt.dateKey(date))
            report.cells.append(MonthCell(
                id: leading + dayNumber,
                inMonth: true,
                key: stats.key,
                dayNumber: dayNumber,
                isToday: stats.key == todayKey,
                focusSeconds: stats.focusSeconds,
                breakSeconds: stats.breakSeconds,
                sessions: stats.sessions
            ))
            report.sessions += stats.sessions
            report.focusSeconds += stats.focusSeconds
            report.breakSeconds += stats.breakSeconds
            report.maxDaySeconds = max(report.maxDaySeconds, stats.focusSeconds)
            if stats.focusSeconds > 0 { report.activeDays += 1 }
        }
        while report.cells.count % 7 != 0 {
            report.cells.append(MonthCell(id: 1000 + report.cells.count, inMonth: false))
        }
        return report
    }

    func allTimeStats() -> AllTimeReport {
        var report = AllTimeReport()
        var activeDays = Set<String>()
        var monthKeys = Set<String>()
        var streakDays = Set<String>()

        for entry in sessions {
            let active = entry.activeSeconds
            let day = Fmt.dateKey(entry.endedAt)
            if entry.phase == .focus {
                report.focusSeconds += active
                if active > 0 {
                    if !day.isEmpty {
                        activeDays.insert(day)
                        monthKeys.insert(String(day.prefix(7)))
                    }
                }
                if entry.isCompletedFocus {
                    report.sessions += 1
                    streakDays.insert(day)
                    if report.firstEndedAt == 0 || entry.endedAt < report.firstEndedAt {
                        report.firstEndedAt = entry.endedAt
                    }
                    if entry.endedAt > report.lastEndedAt { report.lastEndedAt = entry.endedAt }
                } else if active > 0 {
                    report.interrupted += 1
                }
            } else {
                report.breakSeconds += active
                if active > 0 {
                    report.breaks += 1
                    if !day.isEmpty { monthKeys.insert(String(day.prefix(7))) }
                }
                if entry.status != .completed && active > 0 { report.interrupted += 1 }
            }
        }
        report.activeDays = activeDays.count

        let ordered = streakDays.sorted()
        var currentRun = 0
        for (index, key) in ordered.enumerated() {
            if index > 0, let previous = Fmt.dayOrdinal(ordered[index - 1]),
               let current = Fmt.dayOrdinal(key), current == previous + 1 {
                currentRun += 1
            } else {
                currentRun = 1
            }
            report.longestStreak = max(report.longestStreak, currentRun)
        }

        let cal = Fmt.calendar
        var cursor = cal.startOfDay(for: currentDate)
        if !streakDays.contains(Fmt.dateKey(cursor)) {
            cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while streakDays.contains(Fmt.dateKey(cursor)) {
            report.currentStreak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        // The chart shows at most the trailing twelve months of activity.
        let observed = monthKeys.sorted()
        if let firstKey = observed.first, let firstParts = Fmt.monthParts(firstKey) {
            let lastYear = cal.component(.year, from: currentDate)
            let lastMonth = cal.component(.month, from: currentDate) - 1
            let monthCount = (lastYear - firstParts.year) * 12 + lastMonth - firstParts.month + 1
            let firstIndex = max(0, monthCount - 12)
            if monthCount > 0 {
                for offset in firstIndex..<monthCount {
                    let absolute = firstParts.year * 12 + firstParts.month + offset
                    let monthReport = monthlyStats(year: absolute / 12, month: absolute % 12)
                    report.months.append(MonthBar(
                        key: monthReport.key,
                        label: monthReport.shortLabel,
                        focusSeconds: monthReport.focusSeconds,
                        breakSeconds: monthReport.breakSeconds,
                        sessions: monthReport.sessions
                    ))
                }
            }
        }
        report.maxChartSeconds = report.months.map(\.totalSeconds).max() ?? 0
        return report
    }

    /// Position of a timestamp within its day, 0…1, for the timeline.
    func timelineRatio(_ value: EpochMillis, key: String) -> Double {
        guard let start = Fmt.dayStartMillis(forKey: key) else { return 0 }
        return max(0, min(1, (value - start) / 86_400_000))
    }
}
