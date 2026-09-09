import Foundation

/// `Pomodoro --report-dump <file>` writes every report figure as JSON.
/// Tools/qml-reference.js produces the same structure by executing the real
/// functions out of the frozen Service.qml, so the two can be diffed. This is
/// the safety net for the port: the history format and the numbers derived
/// from it must not change.
@MainActor
enum ReportDump {
    static func requestedFile() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--report-dump"),
              index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(into file: URL) {
        let service = AppState.shared.service
        var days: [String: Any] = [:]
        var entries: [String: Any] = [:]
        var weeks: [String: Any] = [:]
        var months: [String: Any] = [:]

        // Every day the history touches, plus the surrounding empty days.
        var keys = Set(service.sessions.map { Fmt.dateKey($0.endedAt) })
        keys.insert(service.todayKey)
        for key in keys.sorted() {
            let stats = service.statsForDay(key)
            days[key] = [
                "sessions": stats.sessions,
                "focusSeconds": stats.focusSeconds,
                "breakSeconds": stats.breakSeconds,
                "breaks": stats.breaks,
                "completedBreaks": stats.completedBreaks,
                "shortBreaks": stats.shortBreaks,
                "longBreaks": stats.longBreaks,
                "interruptedFocus": stats.interruptedFocus,
                "interruptedBreaks": stats.interruptedBreaks,
                "phases": stats.phases,
                "focusText": stats.focusText,
                "breakText": stats.breakText,
                "totalText": stats.totalText
            ]
            entries[key] = service.entriesForDay(key).map { entry in
                [
                    "id": entry.id,
                    "phase": entry.phase.rawValue,
                    "status": entry.status.rawValue,
                    "startedAt": Persistence.millis(entry.startedAt),
                    "endedAt": Persistence.millis(entry.endedAt),
                    "activeSeconds": entry.activeSeconds,
                    "note": entry.note,
                    "segments": entry.segments.map {
                        ["startedAt": Persistence.millis($0.startedAt),
                         "endedAt": Persistence.millis($0.endedAt)]
                    }
                ] as [String: Any]
            }
        }

        for offset in -10...0 {
            guard let anchor = Fmt.calendar.date(byAdding: .day, value: offset * 7,
                                                 to: service.currentDate) else { continue }
            let report = service.weeklyStats(anchor: anchor)
            weeks[report.startKey] = [
                "startKey": report.startKey,
                "endKey": report.endKey,
                "startLabel": report.startLabel,
                "endLabel": report.endLabel,
                "sessions": report.sessions,
                "focusSeconds": report.focusSeconds,
                "breakSeconds": report.breakSeconds,
                "maxTotalSeconds": report.maxTotalSeconds,
                "averageDayText": report.averageDayText,
                "days": report.days.map {
                    ["key": $0.key, "label": $0.label, "dayNumber": $0.dayNumber,
                     "sessions": $0.sessions, "breaks": $0.breaks,
                     "focusSeconds": $0.focusSeconds, "breakSeconds": $0.breakSeconds]
                }
            ]
        }

        for offset in -12...0 {
            guard let date = Fmt.calendar.date(byAdding: .month, value: offset,
                                               to: service.currentDate) else { continue }
            let year = Fmt.calendar.component(.year, from: date)
            let month = Fmt.calendar.component(.month, from: date) - 1
            let report = service.monthlyStats(year: year, month: month)
            months[report.key] = [
                "key": report.key,
                "label": report.label,
                "shortLabel": report.shortLabel,
                "sessions": report.sessions,
                "focusSeconds": report.focusSeconds,
                "breakSeconds": report.breakSeconds,
                "activeDays": report.activeDays,
                "maxDaySeconds": report.maxDaySeconds,
                "cellCount": report.cells.count
            ]
        }

        let all = service.allTimeStats()
        let allTime: [String: Any] = [
            "sessions": all.sessions,
            "focusSeconds": all.focusSeconds,
            "breakSeconds": all.breakSeconds,
            "breaks": all.breaks,
            "activeDays": all.activeDays,
            "currentStreak": all.currentStreak,
            "longestStreak": all.longestStreak,
            "interrupted": all.interrupted,
            "firstEndedAt": Persistence.millis(all.firstEndedAt),
            "lastEndedAt": Persistence.millis(all.lastEndedAt),
            "averageSessionText": all.averageSessionText,
            "maxChartSeconds": all.maxChartSeconds,
            "months": all.months.map {
                ["key": $0.key, "label": $0.label, "focusSeconds": $0.focusSeconds,
                 "breakSeconds": $0.breakSeconds, "sessions": $0.sessions]
            }
        ]

        let payload: [String: Any] = [
            "todayKey": service.todayKey,
            "sessionCount": service.sessions.count,
            "days": days,
            "entries": entries,
            "weeks": weeks,
            "months": months,
            "allTime": allTime
        ]
        try? Persistence.json(payload).write(to: file, atomically: true, encoding: .utf8)
        print("wrote \(file.path)")
        exit(0)
    }
}
