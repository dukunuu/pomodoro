import SwiftUI
import Charts

struct WeekReportView: View {
    @EnvironmentObject private var service: PomodoroService
    @Binding var offset: Int

    private var anchor: Date {
        Fmt.calendar.date(byAdding: .day, value: offset * 7,
                          to: Fmt.calendar.startOfDay(for: service.currentDate)) ?? service.currentDate
    }

    var body: some View {
        let report = service.weeklyStats(anchor: anchor)

        Card {
            PeriodStepper(
                title: "\(report.startLabel) – \(report.endLabel)",
                subtitle: "\(report.focusText) focus · \(report.sessions) sessions · \(report.averageDayText)/day average",
                canGoForward: offset < 0,
                onBack: { offset -= 1 },
                onForward: { offset += 1 },
                onToday: { offset = 0 }
            )

            Chart {
                ForEach(report.days) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Focus", Double(day.focusSeconds) / 3600)
                    )
                    .foregroundStyle(by: .value("Kind", "Focus"))
                    .cornerRadius(3)

                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Break", Double(day.breakSeconds) / 3600)
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
            .frame(height: 220)
        }

        Card("Days") {
            VStack(spacing: 0) {
                ForEach(report.days) { day in
                    HStack(spacing: 10) {
                        Text(day.label)
                            .font(.system(size: 12, weight: day.isToday ? .semibold : .regular))
                            .frame(width: 40, alignment: .leading)
                            .foregroundStyle(day.isToday ? Theme.focus : .primary)
                        Text(String(day.dayNumber))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textMuted.opacity(0.7))
                            .frame(width: 20, alignment: .trailing)

                        GeometryReader { geo in
                            let maximum = max(1, report.maxTotalSeconds)
                            HStack(spacing: 2) {
                                Capsule().fill(Theme.focus)
                                    .frame(width: geo.size.width * CGFloat(day.focusSeconds) / CGFloat(maximum))
                                Capsule().fill(Theme.shortBreak.opacity(0.7))
                                    .frame(width: geo.size.width * CGFloat(day.breakSeconds) / CGFloat(maximum))
                                Spacer(minLength: 0)
                            }
                            .frame(height: 8)
                            .frame(maxHeight: .infinity)
                        }
                        .frame(height: 18)

                        Text(day.focusText)
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 62, alignment: .trailing)
                        Text("\(day.sessions)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .padding(.vertical, 5)
                    if day.id != report.days.last?.id { Rectangle().fill(Theme.border).frame(height: 1) }
                }
            }
        }
    }
}
