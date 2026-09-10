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
            ProgressBar(value: service.phaseProgress, color: accent, overtime: service.isOvertime)
                .padding(.horizontal, 14)
                .padding(.top, 11)
            transport
            separator
            stats
            separator
            actions
        }
        .padding(.vertical, 12)
        .frame(width: 272)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .tint(Theme.focus)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(accent)
                .frame(width: 7, height: 7)
                .shadow(color: service.running ? accent.opacity(0.8) : .clear, radius: 3)
            Text(service.phaseLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textBright)
            Spacer()
            Text(service.statusLabel.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(service.isOvertime ? Theme.urgent : Theme.textMuted)
        }
        .padding(.horizontal, 14)
    }

    private var clock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(service.remainingText)
                .font(Theme.clockFont(38))
                .foregroundStyle(service.isOvertime ? Theme.urgent : Theme.textBright)
                .contentTransition(.numericText())
            Spacer()
            if service.phaseStartedAt > 0 {
                Text("\(Fmt.reportDuration(service.phaseElapsed(at: nowMillis()))) in")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
    }

    private var transport: some View {
        HStack(spacing: 6) {
            PanelButton(title: service.running ? "Pause" : "Start",
                        systemImage: service.running ? "pause.fill" : "play.fill",
                        prominent: true,
                        tint: accent,
                        action: service.toggle)
            PanelButton(title: "Skip", systemImage: "forward.end.fill", action: service.skip)
            PanelButton(title: "Reset", systemImage: "arrow.counterclockwise", action: service.reset)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    private var stats: some View {
        HStack(spacing: 0) {
            StatTile(label: "FOCUS", value: today.focusText, detail: "today", accented: true)
            StatTile(label: "SESSIONS", value: String(today.sessions), detail: "completed")
            StatTile(label: "BREAKS", value: today.breakText, detail: "\(today.breaks) taken")
        }
        .padding(.horizontal, 14)
    }

    private var actions: some View {
        VStack(spacing: 1) {
            MenuRow("Open Dashboard", systemImage: "square.grid.2x2", shortcut: "⌘D") {
                state.showDashboard()
            }
            MenuRow("Send today to Whistler", systemImage: "arrow.up.forward.app") {
                state.showDashboard()
                whistler.importDay(service.todayKey)
            }
            .opacity(integrations.whistlerReady && !whistler.importRunning ? 1 : 0.45)
            .disabled(!integrations.whistlerReady || whistler.importRunning)
            MenuRow("Floating timer", systemImage: "macwindow.on.rectangle", trailing: {
                Toggle("", isOn: $preferences.showFloatingTimer)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .tint(Theme.focus)
            })
            MenuRow("Quit Pomodoro", systemImage: "power", shortcut: "⌘Q") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 6)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.border)
            .frame(height: 1)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
    }
}

/// Compact transport button. AppKit's bordered styles do not take a custom
/// palette cleanly, so the panel draws its own.
private struct PanelButton: View {
    var title: String
    var systemImage: String
    var prominent: Bool = false
    var tint: Color = Palette.muted
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage).font(.system(size: 10))
                Text(title).font(.system(size: 12, weight: prominent ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(prominent
                          ? tint.opacity(hovering ? 0.34 : 0.24)
                          : Palette.raised.opacity(hovering ? 1 : 0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(prominent ? tint.opacity(0.65) : Theme.border, lineWidth: 1)
            )
            .foregroundStyle(prominent ? tint : Theme.text)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Slim palette-coloured progress track.
struct ProgressBar: View {
    var value: Double
    var color: Color
    var overtime: Bool = false
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.raised)
                Capsule()
                    .fill(overtime ? Theme.urgent : color)
                    .frame(width: max(height, geo.size.width * max(0, min(1, value))))
                    .animation(.easeOut(duration: 0.25), value: value)
            }
        }
        .frame(height: height)
    }
}
