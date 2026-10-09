import SwiftUI

struct MonthReportView: View {
    @EnvironmentObject private var service: PomodoroService
    @Binding var offset: Int

    private var month: (year: Int, month: Int) {
        let cal = Fmt.calendar
        let base = cal.date(byAdding: .month, value: offset, to: service.currentDate) ?? service.currentDate
        return (cal.component(.year, from: base), cal.component(.month, from: base) - 1)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    var body: some View {
        let report = service.monthlyStats(year: month.year, month: month.month)

        PeriodStepper(
            title: report.label,
            canGoForward: offset < 0,
            onBack: { offset -= 1 },
            onForward: { offset += 1 },
            onToday: { offset = 0 }
        )

        StatStrip {
            StatTile(label: "Focus", value: report.focusText, detail: "active time", tint: Theme.focus)
            StatTile(label: "Breaks", value: report.breakText, detail: "active time")
            StatTile(label: "Sessions", value: String(report.sessions), detail: "completed")
            StatTile(label: "Active days", value: String(report.activeDays), detail: "with focus time")
        }

        Card("Calendar") {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                    Text(name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textFaint)
                }
                ForEach(report.cells) { cell in
                    MonthDayCell(cell: cell, maxSeconds: report.maxDaySeconds)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Text("Less").font(.caption2).foregroundStyle(Theme.textFaint)
                ForEach([0.15, 0.4, 0.65, 0.9], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.focus.opacity(level))
                        .frame(width: 14, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(Theme.textFaint)
                Spacer()
                Text("Peak day \(Fmt.reportDuration(report.maxDaySeconds))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textFaint)
            }
        }
    }
}

/// One heat cell. Intensity is focus time relative to the month's best day,
/// which keeps a light month readable instead of uniformly dim.
struct MonthDayCell: View {
    var cell: MonthCell
    var maxSeconds: Int

    private var intensity: Double {
        guard cell.inMonth, cell.focusSeconds > 0, maxSeconds > 0 else { return 0 }
        return 0.15 + 0.75 * min(1, Double(cell.focusSeconds) / Double(maxSeconds))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(cell.inMonth ? Theme.focus.opacity(intensity) : .clear)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(cell.inMonth ? Theme.trackFill : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(cell.isToday ? Theme.focus : .clear, lineWidth: 1.5)
                )

            if cell.inMonth {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(cell.dayNumber))
                        .font(.caption.weight(cell.isToday ? .bold : .regular).monospacedDigit())
                    if cell.focusSeconds > 0 {
                        Text(cell.focusText)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            }
        }
        .frame(height: 48)
        .help(cell.inMonth ? "\(cell.key)\n\(cell.focusText) focus · \(cell.sessions) sessions" : "")
    }
}
