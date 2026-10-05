import SwiftUI

/// The countdown ring. A pomodoro is a proportion of a fixed span, which a
/// ring shows at a glance far better than a bar does.
struct TimerRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 7
    var overtime: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.trackFill, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    overtime ? Theme.urgent : color,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.25), value: progress)
        }
    }
}

/// Always-visible timer at the top of the detail pane: phase, clock, ring, and
/// the controls. Everything else in the window is a report about it.
struct TimerHeader: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var preferences: Preferences

    private var accent: Color { Theme.color(for: service.phase) }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                TimerRing(progress: service.phaseProgress,
                          color: accent,
                          lineWidth: 5,
                          overtime: service.isOvertime)
                Image(systemName: service.phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(service.isOvertime ? Theme.urgent : accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(service.phaseLabel)
                        .font(.headline)
                    Text(service.statusLabel)
                        .font(.subheadline)
                        .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.secondary))
                }
                Text(service.remainingText)
                    .font(Theme.clockFont(40))
                    .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.primary))
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: service.toggle) {
                        Label(service.running ? "Pause" : "Start",
                              systemImage: service.running ? "pause.fill" : "play.fill")
                            .frame(width: 66)
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
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // The toolbar material, so the timer reads as window chrome pinned
        // below the title bar rather than as the first card on the page.
        .background(.bar)
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
