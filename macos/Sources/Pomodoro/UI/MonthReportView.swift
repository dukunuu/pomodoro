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
            subtitle: "\(report.focusText) focus · \(report.sessions) sessions · \(report.activeDays) active days",
            canGoForward: offset < 0,
            onBack: { offset -= 1 },
            onForward: { offset += 1 },
            onToday: { offset = 0 }
        )

        Card("Calendar") {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                    Text(name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.textMuted.opacity(0.7))
                }
                ForEach(report.cells) { cell in
                    MonthDayCell(cell: cell, maxSeconds: report.maxDaySeconds)
                }
            }
            .padding(.top, 4)

            HStack(spacing: 8) {
                Text("Less").font(.caption2).foregroundStyle(Theme.textMuted.opacity(0.7))
                ForEach([0.15, 0.4, 0.65, 0.9], id: \.self) { level in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.focus.opacity(level))
                        .frame(width: 14, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(Theme.textMuted.opacity(0.7))
                Spacer()
                Text("Peak day \(Fmt.reportDuration(report.maxDaySeconds))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted.opacity(0.7))
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
            RoundedRectangle(cornerRadius: 6)
                .fill(cell.inMonth ? Theme.focus.opacity(intensity) : .clear)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(cell.inMonth ? Palette.raised.opacity(0.75) : .clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(cell.isToday ? Theme.focus : .clear, lineWidth: 1.5)
                )

            if cell.inMonth {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(cell.dayNumber))
                        .font(.system(size: 10, weight: cell.isToday ? .bold : .regular).monospacedDigit())
                    if cell.focusSeconds > 0 {
                        Text(cell.focusText)
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                .padding(5)
            }
        }
        .frame(height: 46)
        .help(cell.inMonth ? "\(cell.key)\n\(cell.focusText) focus · \(cell.sessions) sessions" : "")
    }
}
