import SwiftUI
import Charts

struct AllTimeReportView: View {
    @EnvironmentObject private var service: PomodoroService

    var body: some View {
        let report = service.allTimeStats()

        PageHeading(title: "All time")

        StatStrip {
            StatTile(label: "Focus", value: report.focusText, detail: "active time", tint: Theme.focus)
            StatTile(label: "Breaks", value: report.breakText, detail: "\(report.breaks) taken")
            StatTile(label: "Sessions", value: String(report.sessions), detail: "completed")
            StatTile(label: "Active days", value: String(report.activeDays), detail: "with focus time")
        }

        Card("Habits") {
            HStack(alignment: .top, spacing: 12) {
                StatTile(label: "Current streak", value: String(report.currentStreak), detail: "days")
                StatTile(label: "Longest streak", value: String(report.longestStreak), detail: "days")
                StatTile(label: "Average session", value: report.averageSessionText, detail: "per completed focus")
                StatTile(label: "Interrupted", value: String(report.interrupted), detail: "phases")
            }

            if report.firstEndedAt > 0 {
                RowDivider()
                Text("First session \(Fmt.dateKey(report.firstEndedAt)) · latest \(Fmt.dateKey(report.lastEndedAt))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textFaint)
            }
        }

        Card("Last 12 months") {
            if report.months.isEmpty {
                EmptyHint(text: "No completed sessions yet.", symbol: "chart.bar")
            } else {
                Chart {
                    ForEach(report.months) { month in
                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Focus", Double(month.focusSeconds) / 3600),
                            width: .fixed(26)
                        )
                        .foregroundStyle(by: .value("Kind", "Focus"))
                        .cornerRadius(4)

                        BarMark(
                            x: .value("Month", month.label),
                            y: .value("Break", Double(month.breakSeconds) / 3600),
                            width: .fixed(26)
                        )
                        .foregroundStyle(by: .value("Kind", "Break"))
                        .cornerRadius(4)
                    }
                }
                .chartForegroundStyleScale([
                    "Focus": Theme.focus,
                    "Break": Theme.shortBreak
                ])
                .reportChartStyle()
                .frame(height: 220)

                HStack(spacing: 14) {
                    LegendDot(color: Theme.focus, label: "Focus")
                    LegendDot(color: Theme.shortBreak, label: "Break")
                }
            }
        }
    }
}
