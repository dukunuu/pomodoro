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
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
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
        HStack(spacing: 18) {
            ZStack {
                TimerRing(progress: service.phaseProgress,
                          color: accent,
                          lineWidth: 6,
                          overtime: service.isOvertime)
                Image(systemName: service.phase == .focus ? "brain.head.profile" : "cup.and.saucer.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(service.isOvertime ? Theme.urgent : accent)
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 7) {
                    Text(service.phaseLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(service.statusLabel)
                        .font(.caption)
                        .foregroundStyle(service.isOvertime ? Theme.urgent : .secondary)
                }
                Text(service.remainingText)
                    .font(Theme.clockFont(38))
                    .foregroundStyle(service.isOvertime ? Theme.urgent : Color.primary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                HStack(spacing: 7) {
                    Button(action: service.toggle) {
                        Label(service.running ? "Pause" : "Start",
                              systemImage: service.running ? "pause.fill" : "play.fill")
                            .frame(width: 78)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .keyboardShortcut(.space, modifiers: [])

                    Button(action: service.skip) { Image(systemName: "forward.end.fill") }
                        .help("Record this phase and move to the next")
                    Button(action: service.reset) { Image(systemName: "arrow.counterclockwise") }
                        .help("Record this phase and restart it")
                }
                cycleDots
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Theme.surface)
    }

    private var cycleDots: some View {
        HStack(spacing: 4) {
            let every = max(1, preferences.longBreakEvery)
            let done = service.completedFocus % every
            ForEach(0..<every, id: \.self) { index in
                Circle()
                    .fill(index < done ? Theme.focus : Palette.raised)
                    .frame(width: 6, height: 6)
            }
            Text("\(service.completedFocus) today")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
                .padding(.leading, 3)
        }
    }
}
