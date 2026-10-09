import SwiftUI

/// Always-visible timer at the top of the detail pane, composed the way the
/// menu bar popover is: phase, a large clock, the transport, and a progress
/// line. Everything else in the window is a report about it.
struct TimerHeader: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var preferences: Preferences

    private var accent: Color { Theme.color(for: service.phase) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(accent)
                            .frame(width: 7, height: 7)
                        Text(service.phaseLabel)
                            .font(.system(size: 13, weight: .semibold))
                        Text(service.statusLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.secondary))
                    }
                    Text(service.remainingText)
                        .font(Theme.clockFont(46))
                        .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.primary))
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 9) {
                    HStack(spacing: 6) {
                        Button(action: service.toggle) {
                            Label(service.running ? "Pause" : "Start",
                                  systemImage: service.running ? "pause.fill" : "play.fill")
                                .frame(width: 72)
                        }
                        .buttonStyle(.primary(tint: accent))
                        .keyboardShortcut(.space, modifiers: [])

                        // Icon-only with tooltips, the way the system's own
                        // transport controls read; the titles stay for
                        // VoiceOver.
                        Button(action: service.skip) {
                            Label("Skip", systemImage: "forward.end.fill")
                        }
                        .help("Record this phase and move to the next")
                        .labelStyle(.iconOnly)
                        .buttonStyle(.iconFilled)

                        Button(action: service.reset) {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                        }
                        .help("Record this phase and restart it")
                        .labelStyle(.iconOnly)
                        .buttonStyle(.iconFilled)
                    }
                    .controlSize(.large)

                    cycleDots
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 12)
            .padding(.bottom, 14)

            progressLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // The toolbar material, so the timer reads as window chrome pinned
        // below the title bar rather than as the first card on the page.
        .background(.bar)
    }

    /// The phase's progress, drawn as the header's own bottom edge: it is the
    /// separator from the page, and it fills as the phase runs.
    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.trackFill)
                Rectangle()
                    .fill(service.isOvertime ? Theme.urgent : accent)
                    .frame(width: geo.size.width * max(0, min(1, service.phaseProgress)))
                    .animation(.easeOut(duration: 0.25), value: service.phaseProgress)
            }
        }
        .frame(height: 2)
    }

    private var cycleDots: some View {
        HStack(spacing: 4) {
            let every = max(1, preferences.longBreakEvery)
            let done = service.completedFocus % every
            ForEach(0..<every, id: \.self) { index in
                Circle()
                    .fill(index < done ? Theme.focus : Theme.trackFill)
                    .frame(width: 6, height: 6)
            }
            Text("\(service.completedFocus) today")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        }
    }
}
