import SwiftUI

@main
struct PomodoroApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var state = AppState.shared

    var body: some Scene {
        // The menu bar item is the primary surface on macOS: the countdown is
        // legible without any window open, and the popover carries the same
        // controls the Windows tray menu offers.
        MenuBarExtra {
            MenuBarPanel()
                .environmentObject(state)
                .environmentObject(state.service)
                .environmentObject(state.whistler)
                .environmentObject(state.integrations)
                .environmentObject(state.updates)
                .environmentObject(state.updateInstaller)
                .environmentObject(state.preferences)
        } label: {
            MenuBarLabel(service: state.service, preferences: state.preferences)
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var service: PomodoroService
    @ObservedObject var preferences: Preferences

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            if preferences.menuBarShowsCountdown && service.phaseStartedAt > 0 {
                Text(service.remainingText)
                    .font(.system(size: 12).monospacedDigit())
            }
        }
    }

    private var symbol: String {
        guard service.phaseStartedAt > 0 else { return "timer" }
        if service.phase != .focus { return "cup.and.saucer.fill" }
        return service.running ? "timer" : "pause.circle"
    }
}

/// The menu bar popover: current phase, transport, today at a glance, and the
/// handful of actions worth reaching without opening a window.
struct MenuBarPanel: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus
    @EnvironmentObject private var preferences: Preferences

    private var accent: Color { Theme.color(for: service.phase) }
    private var today: DayStats { service.statsForDay(service.todayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            clock
            ProgressBar(value: service.phaseProgress, color: accent,
                        overtime: service.isOvertime, height: 5)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            transport
            Divider().padding(.horizontal, 14).padding(.vertical, 12)
            stats
            Divider().padding(.horizontal, 14).padding(.vertical, 12)
            actions
        }
        .padding(.vertical, 12)
        .frame(width: 280)
        // No background of its own: the menu bar window already carries the
        // system's popover vibrancy, and painting over it is what made this
        // read as a custom panel rather than a menu.
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
            Text(service.phaseLabel)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(service.statusLabel)
                .font(.system(size: 12))
                .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 14)
    }

    private var clock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(service.remainingText)
                .font(Theme.clockFont(38))
                .foregroundStyle(service.isOvertime ? AnyShapeStyle(Theme.urgent) : AnyShapeStyle(.primary))
                .contentTransition(.numericText())
            Spacer(minLength: 8)
            if service.phaseStartedAt > 0 {
                Text("\(Fmt.reportDuration(service.phaseElapsed(at: nowMillis()))) in")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var transport: some View {
        HStack(spacing: 6) {
            Button(action: service.toggle) {
                Label(service.running ? "Pause" : "Start",
                      systemImage: service.running ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.primary(tint: accent))

            Button(action: service.skip) {
                Label("Skip", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.secondary)
            Button(action: service.reset) {
                Label("Reset", systemImage: "arrow.counterclockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.iconFilled)
            .help("Record this phase and restart it")
        }
        .controlSize(.large)
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            StatTile(label: "Focus", value: today.focusText, detail: "today", accented: true)
            StatTile(label: "Sessions", value: String(today.sessions), detail: "completed")
            StatTile(label: "Breaks", value: today.breakText, detail: "\(today.breaks) taken")
        }
        .padding(.horizontal, 14)
    }

    private var actions: some View {
        VStack(spacing: 1) {
            MenuRow("Open Dashboard", systemImage: "square.grid.2x2", shortcut: "⌘D",
                    action: { state.showDashboard() })
            MenuRow("Send Today to Whistler", systemImage: "arrow.up.forward.app", action: {
                state.showDashboard()
                whistler.importDay(service.todayKey)
            })
            .disabled(!integrations.whistlerReady || whistler.importRunning)
            MenuRow("Floating Timer", systemImage: "macwindow.on.rectangle", trailing: {
                Switch(label: "Floating Timer", isOn: $preferences.showFloatingTimer)
                    .scaleEffect(0.8, anchor: .trailing)
            })
            Divider().padding(.horizontal, 8).padding(.vertical, 4)
            MenuRow("Quit Pomodoro", systemImage: "power", shortcut: "⌘Q",
                    action: { NSApplication.shared.terminate(nil) })
        }
        .padding(.horizontal, 6)
    }
}

/// Slim palette-coloured progress track, for the places that need a specific
/// weight rather than the system bar's.
struct ProgressBar: View {
    var value: Double
    var color: Color
    var overtime: Bool = false
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.trackFill)
                Capsule()
                    .fill(overtime ? Theme.urgent : color)
                    .frame(width: max(height, geo.size.width * max(0, min(1, value))))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
    }
}
