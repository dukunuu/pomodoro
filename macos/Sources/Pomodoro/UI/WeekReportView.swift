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

        PeriodStepper(
            title: "\(report.startLabel) – \(report.endLabel)",
            canGoForward: offset < 0,
            onBack: { offset -= 1 },
            onForward: { offset += 1 },
            onToday: { offset = 0 }
        )

        StatStrip {
            StatTile(label: "Focus", value: report.focusText, detail: "active time", tint: Theme.focus)
            StatTile(label: "Breaks", value: report.breakText, detail: "active time")
            StatTile(label: "Sessions", value: String(report.sessions), detail: "completed")
            StatTile(label: "Daily average", value: report.averageDayText, detail: "focus per day")
        }

        Card("Focus per day") {
            Chart {
                ForEach(report.days) { day in
                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Focus", Double(day.focusSeconds) / 3600),
                        width: .fixed(26)
                    )
                    .foregroundStyle(by: .value("Kind", "Focus"))
                    .cornerRadius(4)

                    BarMark(
                        x: .value("Day", day.label),
                        y: .value("Break", Double(day.breakSeconds) / 3600),
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
            .frame(height: 200)

            HStack(spacing: 14) {
                LegendDot(color: Theme.focus, label: "Focus")
                LegendDot(color: Theme.shortBreak, label: "Break")
            }
        }

        Card("Days") {
            VStack(spacing: 0) {
                ForEach(report.days) { day in
                    HStack(spacing: 10) {
                        Text(day.label)
                            .font(.callout.weight(day.isToday ? .semibold : .regular))
                            .frame(width: 40, alignment: .leading)
                            .foregroundStyle(day.isToday ? AnyShapeStyle(Theme.focus) : AnyShapeStyle(.primary))
                        Text(String(day.dayNumber))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textFaint)
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
                            .font(.callout.monospacedDigit())
                            .frame(width: 62, alignment: .trailing)
                        Text("\(day.sessions)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                            .frame(width: 26, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                    if day.id != report.days.last?.id { RowDivider() }
                }
            }
        }
    }
}

extension View {
    /// The axis treatment the bar charts share: hours down the trailing edge,
    /// hairline rules, no vertical grid, and no legend of the chart's own —
    /// the card sets one in the same dots the timeline uses.
    func reportChartStyle() -> some View {
        self
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks { _ in
                    AxisValueLabel()
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Theme.hairline)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(hours.formatted(.number.precision(.fractionLength(0...1))))h")
                        }
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textFaint)
                }
            }
    }
}
