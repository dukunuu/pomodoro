import SwiftUI
import AppKit

/// App settings as one grouped Form — the shape System Settings uses, so the
/// rows, insets and control alignment are AppKit's rather than hand-drawn.
/// Google setup and sending live on the Whistler page; the account, model and
/// key are settings, so they can be changed without revisiting setup.
struct SettingsPanel: View {
    var body: some View {
        Form {
            TimerSettingsSection()
            BehaviourSection()
            WhistlerAccountSection()
            AISection()
            UpdatesSection()
            DataSection()
        }
        .formStyle(.grouped)
    }
}

struct TimerSettingsSection: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Section {
            durationRow("Focus", value: $preferences.focusMinutes, phase: .focus)
            durationRow("Short break", value: $preferences.shortBreakMinutes, phase: .short)
            durationRow("Long break", value: $preferences.longBreakMinutes, phase: .long)
            LabeledContent("Long break every") {
                Stepper(value: $preferences.longBreakEvery, in: 1...12) {
                    Text("\(preferences.longBreakEvery) focus sessions")
                        .monospacedDigit()
                }
            }
        } header: {
            Text("Timer")
        } footer: {
            Text("Changing a duration applies to the next phase; a phase already running keeps its deadline.")
        }
    }

    /// Label at the leading edge, stepper at the trailing one — the row shape
    /// a grouped Form lays out for itself. The phase colour leads the row.
    private func durationRow(_ label: String, value: Binding<Int>, phase: Phase) -> some View {
        LabeledContent {
            Stepper(value: value, in: 1...240) {
                Text("\(value.wrappedValue) min").monospacedDigit()
            }
        } label: {
            Label {
                Text(label)
            } icon: {
                Circle()
                    .fill(Theme.color(for: phase))
                    .frame(width: 9, height: 9)
            }
        }
    }
}

struct BehaviourSection: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Section("Behavior") {
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

struct UpdatesSection: View {
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var installer: UpdateInstaller
    @State private var enabled = true
    @State private var checkedNow = false

    var body: some View {
        Section("Updates") {
            LabeledContent("Current version") {
                Text(updates.currentVersion).monospacedDigit()
            }

            Toggle(isOn: $enabled) {
                Text("Check GitHub for new releases on launch")
                Text("Once a day at most. Updates install only when you choose to.")
            }
            .onChange(of: enabled) { _, value in updates.enabled = value }

            LabeledContent {
                HStack(spacing: 8) {
                    if let update = updates.available {
                        Button(installer.stage.isBusy ? "Updating…" : "Update to \(update.version)") {
                            Task { await installer.install(update) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(installer.stage.isBusy)
                    }
                    Button(updates.checking ? "Checking…" : "Check Now") {
                        checkedNow = false
                        Task {
                            await updates.check(force: true)
                            checkedNow = true
                        }
                    }
                    .disabled(updates.checking)
                }
            } label: {
                if let error = updates.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.urgent)
                } else if checkedNow && updates.available == nil {
                    Label("You are on the latest release.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.longBreak)
                }
            }
        }
    }
}

struct DataSection: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var integrations: IntegrationStatus

    var body: some View {
        Section {
            pathRow("History and state", DataPaths.directory.path)
            pathRow("Integration bridges", DataPaths.scriptsDirectory.path)
            pathRow("Python", Bridge.pythonPath)

            if !integrations.python.isReady {
                Label(integrations.python.detail, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.urgent)
            }

            LabeledContent("Data folder") {
                Button("Show in Finder") { state.openDataDirectory() }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("The Python bridges read and write these same files.")
        }
    }

    private func pathRow(_ label: String, _ value: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }
}
