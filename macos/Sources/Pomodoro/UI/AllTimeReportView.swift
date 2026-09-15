import SwiftUI
import Charts

struct AllTimeReportView: View {
    @EnvironmentObject private var service: PomodoroService

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        let report = service.allTimeStats()

        PageHeading(
            title: "All time",
            subtitle: "\(report.focusText) focus · \(report.sessions) sessions · \(report.activeDays) active days")

        Card("Totals") {
            LazyVGrid(columns: columns, spacing: 14) {
                StatTile(label: "Completed focus", value: String(report.sessions), detail: "sessions", accented: true)
                StatTile(label: "Focus time", value: report.focusText, detail: "active")
                StatTile(label: "Break time", value: report.breakText, detail: "active")
                StatTile(label: "Breaks taken", value: String(report.breaks), detail: "breaks")
                StatTile(label: "Active days", value: String(report.activeDays), detail: "with focus time")
                StatTile(label: "Current streak", value: String(report.currentStreak), detail: "days", accented: true)
                StatTile(label: "Longest streak", value: String(report.longestStreak), detail: "days")
                StatTile(label: "Average session", value: report.averageSessionText, detail: "per completed focus")
            }

            if report.firstEndedAt > 0 {
                Text("First session \(Fmt.dateKey(report.firstEndedAt)) · latest \(Fmt.dateKey(report.lastEndedAt)) · \(report.interrupted) interrupted phases")
                    .font(.caption2)
                    .foregroundStyle(Theme.textFaint)
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
                            y: .value("Focus", Double(month.focusSeconds) / 3600),
                            width: .fixed(26)
                        )
                        .foregroundStyle(by: .value("Kind", "Focus"))
                        .cornerRadius(3)

                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Break", Double(month.breakSeconds) / 3600),
                            width: .fixed(26)
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
