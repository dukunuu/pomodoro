import SwiftUI
import AppKit

/// App settings only. Everything Whistler- and Google-related lives in the
/// Whistler section, next to the button that depends on it.
struct SettingsPanel: View {
    var body: some View {
        TimerSettingsCard()
        BehaviourCard()
        UpdatesCard()
        DataCard()
    }
}

struct TimerSettingsCard: View {
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var service: PomodoroService

    var body: some View {
        Card("Timer") {
            VStack(spacing: 9) {
                durationRow("Focus", value: $preferences.focusMinutes, phase: .focus)
                durationRow("Short break", value: $preferences.shortBreakMinutes, phase: .short)
                durationRow("Long break", value: $preferences.longBreakMinutes, phase: .long)
                HStack(spacing: 10) {
                    Circle().fill(Color.clear).frame(width: 7, height: 7)
                    Text("Long break every")
                    Spacer(minLength: 16)
                    Stepper(value: $preferences.longBreakEvery, in: 1...12) {
                        Text("\(preferences.longBreakEvery) focus sessions")
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
            }
            .font(.callout)

            Text("Changing a duration applies to the next phase; a phase already running keeps its deadline.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Label at the leading edge, control at the trailing one — the shape
    /// every other settings row in the app already has. The phase colour
    /// leads the row rather than trailing it as a loose dot.
    private func durationRow(_ label: String, value: Binding<Int>, phase: Phase) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Theme.color(for: phase))
                .frame(width: 7, height: 7)
            Text(label)
            Spacer(minLength: 16)
            Stepper(value: value, in: 1...240) {
                Text("\(value.wrappedValue) min").monospacedDigit()
            }
            .fixedSize()
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

struct UpdatesCard: View {
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var installer: UpdateInstaller
    @Environment(\.openURL) private var openURL
    @State private var enabled = true
    @State private var checkedNow = false

    var body: some View {
        Card("Updates") {
            HStack {
                Text("Current version")
                    .font(.callout)
                    .foregroundStyle(Theme.text)
                Spacer()
                Text(updates.currentVersion)
                    .font(.callout.monospaced())
                    .foregroundStyle(Theme.textMuted)
            }

            Toggle(isOn: $enabled) {
                Text("Check GitHub for new releases on launch")
                Text("Once a day at most. Updates install only when you choose to.")
            }
            .onChange(of: enabled) { _, value in updates.enabled = value }

            HStack(spacing: 8) {
                Button(updates.checking ? "Checking…" : "Check now") {
                    checkedNow = false
                    Task {
                        await updates.check(force: true)
                        checkedNow = true
                    }
                }
                .disabled(updates.checking)

                if let update = updates.available {
                    Button(installer.stage.isBusy ? "Updating…" : "Update to \(update.version)") {
                        Task { await installer.install(update) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.focus)
                    .disabled(installer.stage.isBusy)
                } else if let error = updates.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.urgent)
                } else if checkedNow {
                    Label("You are on the latest release.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.longBreak)
                }
                Spacer()
            }
        }
        .onAppear { enabled = updates.enabled }
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
