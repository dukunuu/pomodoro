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

        PeriodStepper(
            title: Fmt.dayLabel(date),
            subtitle: "\(stats.focusText) focus · \(stats.breakText) break · \(stats.phases) phases",
            canGoForward: offset < 0,
            onBack: { offset -= 1 },
            onForward: { offset += 1 },
            onToday: { offset = 0 }
        )

        Card("Timeline") {
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
                    .foregroundStyle(Theme.textFaint)
            }
        }

        Card("Phases") {
            if entries.isEmpty {
                EmptyHint(text: "No phases recorded for this day yet.")
            } else {
                VStack(spacing: 0) {
                    ForEach(entries.reversed()) { entry in
                        EntryRow(entry: entry)
                        if entry.id != entries.first?.id { Divider() }
                    }
                }
            }
        }
    }
}

/// A band showing when the clock was actually running. Pauses leave gaps,
/// which is the point: the row is working time, not wall-clock span.
///
/// It spans the working day rather than all 24 hours — a half-hour session on
/// a midnight-to-midnight axis is a sliver — and widens to take in anything
/// recorded outside it.
struct DayTimeline: View {
    var entries: [SessionEntry]
    var key: String
    var service: PomodoroService

    private struct Window {
        var start: Double
        var end: Double
        var step: Double
        var span: Double { end - start }
        var hours: [Double] { Array(stride(from: start, through: end, by: step)) }
    }

    private var window: Window {
        var first = 24.0, last = 0.0
        for entry in entries {
            for segment in entry.segments {
                first = min(first, service.timelineRatio(segment.startedAt, key: key) * 24)
                last = max(last, service.timelineRatio(segment.endedAt, key: key) * 24)
            }
        }
        if key == service.todayKey {
            let now = service.timelineRatio(nowMillis(), key: key) * 24
            first = min(first, now)
            last = max(last, now)
        }
        var start = 8.0, end = 18.0
        if first < last {
            start = min(start, (first - 0.5).rounded(.down))
            end = max(end, (last + 0.5).rounded(.up))
        }
        let step: Double = end - start <= 12 ? 2 : (end - start <= 18 ? 3 : 4)
        start = max(0, (start / step).rounded(.down) * step)
        end = min(24, (end / step).rounded(.up) * step)
        return Window(start: start, end: end, step: step)
    }

    var body: some View {
        let window = self.window
        let place = { (ratio: Double) -> CGFloat in
            CGFloat(max(0, min(1, (ratio * 24 - window.start) / window.span)))
        }

        VStack(spacing: 4) {
            GeometryReader { geo in
                let width = geo.size.width
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Theme.trackFill)

                    ForEach(window.hours.dropFirst().dropLast(), id: \.self) { hour in
                        Rectangle()
                            .fill(Theme.border)
                            .frame(width: 1)
                            .offset(x: width * CGFloat((hour - window.start) / window.span))
                    }

                    ForEach(entries) { entry in
                        ForEach(Array(entry.segments.enumerated()), id: \.offset) { _, segment in
                            let start = place(service.timelineRatio(segment.startedAt, key: key))
                            let end = place(service.timelineRatio(segment.endedAt, key: key))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Theme.color(for: entry.phase).opacity(entry.isLive ? 0.95 : 0.75))
                                .frame(width: max(3, width * (end - start)))
                                .offset(x: width * start)
                                .help(tooltip(entry))
                        }
                    }

                    if key == service.todayKey {
                        Capsule()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 2)
                            .padding(.vertical, -3)
                            .offset(x: width * place(service.timelineRatio(nowMillis(), key: key)) - 1)
                            .help("Now")
                    }
                }
            }
            .frame(height: 42)

            GeometryReader { geo in
                ForEach(window.hours, id: \.self) { hour in
                    Text(String(format: "%02d:00", Int(hour)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(Theme.textFaint)
                        .fixedSize()
                        .position(
                            x: min(max(geo.size.width * CGFloat((hour - window.start) / window.span), 16),
                                   geo.size.width - 16),
                            y: geo.size.height / 2)
                }
            }
            .frame(height: 14)
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
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.textMuted)
                .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.phase.label)
                    .font(.callout)
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
                .font(.callout.weight(.medium).monospacedDigit())
                .frame(width: 62, alignment: .trailing)
        }
        .padding(.vertical, 7)
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
            .foregroundStyle(Theme.textFaint)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 18)
    }
}
