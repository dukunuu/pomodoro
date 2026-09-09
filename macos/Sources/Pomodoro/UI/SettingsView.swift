import SwiftUI
import AppKit

/// App settings only. Everything Whistler- and Google-related lives in the
/// Whistler section, next to the button that depends on it.
struct SettingsPanel: View {
    var body: some View {
        TimerSettingsCard()
        BehaviourCard()
        DataCard()
    }
}

struct TimerSettingsCard: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var service: PomodoroService

    var body: some View {
        Card("Timer") {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 9) {
                durationRow("Focus", value: $preferences.focusMinutes, phase: .focus)
                durationRow("Short break", value: $preferences.shortBreakMinutes, phase: .short)
                durationRow("Long break", value: $preferences.longBreakMinutes, phase: .long)
                GridRow {
                    Text("Long break every")
                    Stepper(value: $preferences.longBreakEvery, in: 1...12) {
                        Text("\(preferences.longBreakEvery) focus sessions")
                            .monospacedDigit()
                    }
                    Color.clear.frame(height: 1)
                }
            }
            .font(.callout)

            Text("Changing a duration applies to the next phase; a phase already running keeps its deadline.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func durationRow(_ label: String, value: Binding<Int>, phase: Phase) -> some View {
        GridRow {
            Text(label)
            Stepper(value: value, in: 1...240) {
                Text("\(value.wrappedValue) min").monospacedDigit()
            }
            Circle()
                .fill(Theme.color(for: phase))
                .frame(width: 7, height: 7)
        }
    }
}

struct BehaviourCard: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Card("Behavior") {
            Toggle(isOn: $preferences.showFloatingTimer) {
                Text("Floating timer window")
                Text("Stays above other windows without taking focus.")
            }
            Toggle(isOn: $preferences.menuBarShowsCountdown) {
                Text("Countdown in the menu bar")
                Text("Shows the remaining time beside the menu bar icon.")
            }
            Toggle(isOn: $preferences.playAlarmSound) {
                Text("Sound when a phase ends")
                Text("Plays alongside the Notification Center alert.")
            }
        }
    }
}

struct DataCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var integrations: IntegrationStatus

    var body: some View {
        Card("Data") {
            pathRow("History and state", DataPaths.directory.path)
            pathRow("Integration bridges", DataPaths.scriptsDirectory.path)
            pathRow("Python", Bridge.pythonPath)

            if !integrations.python.isReady {
                Label(integrations.python.detail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.urgent)
            }

            Text("The Python bridges read and write these same files.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.7))

            HStack(spacing: 8) {
                Button("Open data folder") { state.openDataDirectory() }
                Spacer()
            }
        }
    }

    private func pathRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .frame(width: 130, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}
