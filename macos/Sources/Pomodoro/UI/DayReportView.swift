import SwiftUI

struct DayReportView: View {
    @EnvironmentObject private var service: PomodoroService
    @Binding var offset: Int

    private var date: Date {
        Fmt.calendar.date(byAdding: .day, value: offset,
                          to: Fmt.calendar.startOfDay(for: service.currentDate)) ?? service.currentDate
    }
    private var key: String { Fmt.dateKey(date) }

    var body: some View {
        let stats = service.statsForDay(key)
        let entries = service.entriesForDay(key)

        Card {
            PeriodStepper(
                title: Fmt.dayLabel(date),
                subtitle: "\(stats.focusText) focus · \(stats.breakText) break · \(stats.phases) phases",
                canGoForward: offset < 0,
                onBack: { offset -= 1 },
                onForward: { offset += 1 },
                onToday: { offset = 0 }
            )

            DayTimeline(entries: entries, key: key, service: service)
                .frame(height: 62)
                .padding(.top, 2)

            HStack(spacing: 14) {
                LegendDot(color: Theme.focus, label: "Focus")
                LegendDot(color: Theme.shortBreak, label: "Short break")
                LegendDot(color: Theme.longBreak, label: "Long break")
                Spacer()
                Text("\(stats.interruptedFocus) interrupted focus · \(stats.completedBreaks) breaks completed")
                    .font(.caption2)
                    .foregroundStyle(Theme.textMuted.opacity(0.7))
            }
        }

        Card("Phases") {
            if entries.isEmpty {
                EmptyHint(text: "No phases recorded for this day yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.reversed()) { entry in
                        EntryRow(entry: entry)
                        if entry.id != entries.first?.id { Rectangle().fill(Theme.border).frame(height: 1) }
                    }
                }
            }
        }
    }
}

/// A 24-hour band showing when the clock was actually running. Pauses leave
/// gaps, which is the point: the row is working time, not wall-clock span.
struct DayTimeline: View {
    var entries: [SessionEntry]
    var key: String
    var service: PomodoroService

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Palette.raised)

                    // Three-hour gridlines.
                    ForEach(1..<8) { index in
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: 1)
                            .offset(x: width * CGFloat(index) / 8)
                    }

                    ForEach(entries) { entry in
                        ForEach(Array(entry.segments.enumerated()), id: \.offset) { _, segment in
                            let start = service.timelineRatio(segment.startedAt, key: key)
                            let end = service.timelineRatio(segment.endedAt, key: key)
                            let barWidth = max(2, width * CGFloat(end - start))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.color(for: entry.phase).opacity(entry.isLive ? 0.95 : 0.75))
                                .frame(width: barWidth)
                                .offset(x: width * CGFloat(start))
                                .help(tooltip(entry))
                        }
                    }
                }
            }
            .frame(height: 42)

            HStack(spacing: 0) {
                ForEach(0..<9) { index in
                    Text(index == 8 ? "24" : "\(index * 3)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(Theme.textMuted.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: index == 0 ? .leading : (index == 8 ? .trailing : .center))
                }
            }
        }
    }

    private func tooltip(_ entry: SessionEntry) -> String {
        var text = "\(entry.phase.label) · \(Fmt.rangeLabel(entry))"
        text += "\n\(Fmt.reportDuration(entry.activeSeconds)) active · \(entry.status.label)"
        if !entry.note.isEmpty { text += "\n\(entry.note)" }
        return text
    }
}

struct EntryRow: View {
    var entry: SessionEntry

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.color(for: entry.phase))
                .frame(width: 8, height: 8)
                .opacity(entry.status == .completed || entry.isLive ? 1 : 0.4)

            Text(Fmt.rangeLabel(entry))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.phase.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.text)
                if !entry.note.isEmpty {
                    Text(entry.note)
                        .font(.caption2)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            Text(entry.isLive ? "in progress" : entry.status.label)
                .font(.caption2)
                .foregroundStyle(entry.isLive ? Theme.focus : Theme.textMuted)

            Text(Fmt.reportDuration(entry.activeSeconds))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textBright)
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }
}

struct LegendDot: View {
    var color: Color
    var label: String

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundStyle(Theme.textMuted)
        }
    }
}

struct EmptyHint: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(Theme.textMuted.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
    }
}
