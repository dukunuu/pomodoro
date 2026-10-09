import SwiftUI
import AppKit

/// App settings as cards of rows, in the same column and the same controls as
/// every other page. Whistler and the standup are configured from their own
/// pages, in sheets, so this page is only about the app itself.
struct SettingsPanel: View {
    var body: some View {
        TimerSettingsSection()
        BehaviourSection()
        UpdatesSection()
        DataSection()
    }
}

struct TimerSettingsSection: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Card("Timer",
             subtitle: "Changing a duration applies to the next phase; a phase already running keeps its deadline.") {
            VStack(spacing: 9) {
                durationRow("Focus", value: $preferences.focusMinutes, phase: .focus)
                RowDivider()
                durationRow("Short break", value: $preferences.shortBreakMinutes, phase: .short)
                RowDivider()
                durationRow("Long break", value: $preferences.longBreakMinutes, phase: .long)
                RowDivider()
                SettingRow("Long break every", subtitle: "Focus sessions before the longer rest.") {
                    StepperField(label: "Long break every",
                                 value: $preferences.longBreakEvery,
                                 range: 1...12,
                                 unit: preferences.longBreakEvery == 1 ? "session" : "sessions",
                                 valueWidth: 86)
                }
            }
        }
    }

    /// The phase colour leads the row, as it does everywhere a phase appears.
    private func durationRow(_ label: String, value: Binding<Int>, phase: Phase) -> some View {
        SettingRow(label, dot: Theme.color(for: phase)) {
            StepperField(label: label, value: value, range: 1...240, unit: "min")
        }
    }
}

struct BehaviourSection: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Card("Behavior") {
            VStack(spacing: 9) {
                ToggleRow(title: "Floating timer window",
                          subtitle: "Stays above other windows without taking focus.",
                          isOn: $preferences.showFloatingTimer)
                RowDivider()
                ToggleRow(title: "Countdown in the menu bar",
                          subtitle: "Shows the remaining time beside the menu bar icon.",
                          isOn: $preferences.menuBarShowsCountdown)
                RowDivider()
                ToggleRow(title: "Sound when a phase ends",
                          subtitle: "Plays alongside the Notification Center alert.",
                          isOn: $preferences.playAlarmSound)
            }
        }
    }
}

struct UpdatesSection: View {
    @EnvironmentObject private var updates: UpdateChecker
    @EnvironmentObject private var installer: UpdateInstaller
    @State private var enabled = true
    @State private var checkedNow = false

    private var status: (title: String, subtitle: String?, dot: Color?) {
        if let error = updates.lastError {
            return ("Could not check for updates", error, Theme.urgent)
        }
        if let update = updates.available {
            return ("Version \(update.version) is available", update.name, Theme.accent)
        }
        if checkedNow {
            return ("You are on the latest release.", nil, Theme.longBreak)
        }
        return ("Pomodoro \(updates.currentVersion)", "Check whether a newer release exists.", nil)
    }

    var body: some View {
        Card("Updates",
             accessory: AnyView(StatusPill(text: "v\(updates.currentVersion)"))) {
            VStack(spacing: 9) {
                ToggleRow(title: "Check GitHub for new releases on launch",
                          subtitle: "Once a day at most. Updates install only when you choose to.",
                          isOn: $enabled)
                RowDivider()
                SettingRow(status.title, subtitle: status.subtitle, dot: status.dot) {
                    if let update = updates.available {
                        Button(installer.stage.isBusy ? "Updating…" : "Update to \(update.version)") {
                            Task { await installer.install(update) }
                        }
                        .buttonStyle(.primary)
                        .disabled(installer.stage.isBusy)
                    }
                    Button(updates.checking ? "Checking…" : "Check Now") {
                        checkedNow = false
                        Task {
                            await updates.check(force: true)
                            checkedNow = true
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(updates.checking)
                }
            }
        }
        .onAppear { enabled = updates.enabled }
        .onChange(of: enabled) { _, value in updates.enabled = value }
    }
}

struct DataSection: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var integrations: IntegrationStatus

    var body: some View {
        Card("Data",
             subtitle: "The Python bridges read and write these same files.",
             accessory: AnyView(
                Button { state.openDataDirectory() } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
             )) {
            VStack(spacing: 8) {
                pathRow("History and state", DataPaths.directory.path)
                pathRow("Integration bridges", DataPaths.scriptsDirectory.path)
                pathRow("Python", Bridge.pythonPath)
            }

            if !integrations.python.isReady {
                Notice(.error, integrations.python.detail)
            }
        }
    }

    private func pathRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 13))
                .frame(width: 140, alignment: .leading)
            Text(value)
                .font(Theme.mono(11))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9)
                .frame(height: 26)
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .help(value)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            } label: {
                Label("Copy path", systemImage: "doc.on.doc").labelStyle(.iconOnly)
            }
            .buttonStyle(.icon)
            .controlSize(.small)
            .help("Copy path")
        }
    }
}
