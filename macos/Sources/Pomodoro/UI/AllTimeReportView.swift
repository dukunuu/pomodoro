import SwiftUI
import Charts

struct AllTimeReportView: View {
    @EnvironmentObject private var service: PomodoroService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        let report = service.allTimeStats()

        Card("All time") {
            LazyVGrid(columns: columns, spacing: 14) {
                StatTile(label: "COMPLETED FOCUS", value: String(report.sessions), detail: "sessions", accented: true)
                StatTile(label: "FOCUS TIME", value: report.focusText, detail: "active")
                StatTile(label: "BREAK TIME", value: report.breakText, detail: "active")
                StatTile(label: "BREAKS TAKEN", value: String(report.breaks), detail: "breaks")
                StatTile(label: "ACTIVE DAYS", value: String(report.activeDays), detail: "with focus time")
                StatTile(label: "CURRENT STREAK", value: String(report.currentStreak), detail: "days", accented: true)
                StatTile(label: "LONGEST STREAK", value: String(report.longestStreak), detail: "days")
                StatTile(label: "AVERAGE SESSION", value: report.averageSessionText, detail: "per completed focus")
            }

            if report.firstEndedAt > 0 {
                Text("First session \(Fmt.dateKey(report.firstEndedAt)) · latest \(Fmt.dateKey(report.lastEndedAt)) · \(report.interrupted) interrupted phases")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted.opacity(0.7))
                    .padding(.top, 2)
            }
        }

        Card("Last 12 months") {
            if report.months.isEmpty {
                EmptyHint(text: "No completed sessions yet.")
            } else {
                Chart {
                    ForEach(report.months) { month in
                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Focus", Double(month.focusSeconds) / 3600)
                        )
                        .foregroundStyle(by: .value("Kind", "Focus"))
                        .cornerRadius(3)

                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Break", Double(month.breakSeconds) / 3600)
                        )
                        .foregroundStyle(by: .value("Kind", "Break"))
                        .cornerRadius(3)
                    }
                }
                .chartForegroundStyleScale([
                    "Focus": Theme.focus,
                    "Break": Theme.shortBreak
                ])
                .chartYAxisLabel("hours")
                .frame(height: 240)
            }
        }
    }
}
