import SwiftUI
import Charts
import AppKit

/// Everything about getting the day into Whistler: what setup is still
/// outstanding, the send control itself, and how the month is tracking.
struct WhistlerView: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus

    var body: some View {
        if !integrations.whistlerReady {
            SetupChecklistCard()
        }
        SendCard()
        ReminderCard()
        WhistlerMonthCard()
        InstructionsCard()
    }
}

/// The send control. Prominent, states its own preconditions, and reports what
/// happened rather than leaving a bridge to fail silently.
struct SendCard: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus

    @State private var day = Date()

    private var key: String { Fmt.dateKey(day) }
    private var isToday: Bool { key == service.todayKey }
    private var alreadySent: Bool { whistler.isDayImported(key) }
    private var ready: Bool { integrations.whistlerReady }

    var body: some View {
        Card("Send to Whistler") {
            HStack(alignment: .center, spacing: 12) {
                DatePicker("Day", selection: $day, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .frame(width: 116)

                if !isToday {
                    Button("Today") { day = Date() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }

                Spacer(minLength: 8)

                if whistler.importRunning {
                    Button("Cancel") { whistler.cancelImport() }
                }

                Button {
                    whistler.importDay(key)
                } label: {
                    Label(whistler.importRunning ? "Sending…" : "Send \(isToday ? "today" : key)",
                          systemImage: "arrow.up.forward.app")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.focus)
                .controlSize(.large)
                .disabled(whistler.importRunning || !ready)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            if whistler.importRunning {
                VStack(alignment: .leading, spacing: 5) {
                    ProgressBar(value: Double(whistler.importProgress) / 100, color: Theme.focus)
                    Text(whistler.importStatus.isEmpty ? "Working…" : whistler.importStatus)
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(2)
                }
            } else if !whistler.importStatus.isEmpty {
                Label(whistler.importStatus,
                      systemImage: whistler.importProgress == 100
                          ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(whistler.importProgress == 100 ? Theme.longBreak : Theme.urgent)
            }

            HStack(spacing: 10) {
                if !ready {
                    Label("Finish the setup above before sending.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                } else if alreadySent {
                    Label("\(key) has already been sent. Sending again updates it.",
                          systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                } else {
                    Text("Reads that day's Google Calendar events, classifies them, and writes the worklog.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
                if FileManager.default.fileExists(atPath: DataPaths.directory
                    .appendingPathComponent("pomodoro-whistler.log").path) {
                    Button("Open log") {
                        NSWorkspace.shared.open(DataPaths.directory
                            .appendingPathComponent("pomodoro-whistler.log"))
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
        }
    }
}

/// The setup steps, in the order they have to happen, each with live state.
struct SetupChecklistCard: View {
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus
    @State private var showingGoogleHelp = false
    @State private var showingCredentials = false
    @State private var installError: String?

    var body: some View {
        card.sheet(isPresented: $showingCredentials) {
            WhistlerCredentialsSheet { integrations.refresh() }
        }
    }

    private var card: some View {
        Card("Setup") {
            Text("Whistler needs a Google Calendar client, an authorized Google account, and your Whistler credentials.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            SetupRow(
                number: 1,
                title: "Google OAuth client",
                state: integrations.googleClient,
                actionTitle: integrations.googleClient.isReady ? "Replace…" : "Install…"
            ) { showingGoogleHelp = true }

            SetupRow(
                number: 2,
                title: "Authorize Google account",
                state: integrations.googleToken,
                actionTitle: integrations.googleToken.isReady ? "Re-authorize" : "Authorize",
                enabled: integrations.googleClient.isReady
            ) { whistler.authorizeGoogle() }

            SetupRow(
                number: 3,
                title: "Whistler credentials",
                state: integrations.whistler,
                actionTitle: integrations.whistler.isReady ? "Reconfigure" : "Configure",
                enabled: integrations.googleToken.isReady
            ) { showingCredentials = true }

            if !integrations.python.isReady {
                Label(integrations.python.detail, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.urgent)
            }

            if !integrations.whistlerSummary.isEmpty {
                Divider().padding(.vertical, 2)
                ForEach(integrations.whistlerSummary, id: \.0) { item in
                    HStack {
                        Text(item.0).font(.caption).foregroundStyle(Theme.textMuted)
                        Spacer()
                        Text(item.1).font(.caption.monospaced()).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
        .sheet(isPresented: $showingGoogleHelp) {
            GoogleClientSheet(installError: $installError)
        }
    }
}

struct SetupRow: View {
    var number: Int
    var title: String
    var state: SetupState
    var actionTitle: String
    var enabled: Bool = true
    var action: () -> Void

    private var tint: Color {
        switch state {
        case .ready: return Theme.longBreak
        case .blocked: return Theme.urgent
        case .missing: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.symbol)
                .foregroundStyle(tint)
                .font(.system(size: 14))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(number). \(title)").font(.callout)
                Text(state.detail).font(.caption).foregroundStyle(Theme.textMuted)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .disabled(!enabled)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
        .opacity(enabled ? 1 : 0.55)
    }
}

/// Explains where the client JSON comes from, then installs the chosen file.
/// This is the step that previously failed with a missing-file error.
struct GoogleClientSheet: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @Environment(\.dismiss) private var dismiss
    @Binding var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Install a Google OAuth client")
                .font(.headline)

            Text("""
            The bridges sign in with your own Google Cloud OAuth client; no \
            credentials ship with the app. Create one once:
            """)
                .font(.callout)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                step(1, "Open Google Cloud Console → APIs & Services → Credentials.")
                step(2, "Enable the Google Calendar API for the project.")
                step(3, "Create Credentials → OAuth client ID → Desktop app.")
                step(4, "Download the JSON, then choose it below.")
            }

            HStack(spacing: 8) {
                Button("Open Google Cloud Console") {
                    NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
                }
                Button("Choose client JSON…") { chooseFile() }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }

            if let installError {
                Label(installError, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.urgent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("It is copied to \(DataPaths.googleClient.path) and never leaves this Mac.")
                .font(.caption2)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 7) {
            Text("\(number).")
                .font(.callout.monospacedDigit())
                .foregroundStyle(Theme.textMuted.opacity(0.7))
            Text(text).font(.callout)
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choose the OAuth client JSON downloaded from Google Cloud."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        installError = integrations.installGoogleClient(from: url)
        if installError == nil { dismiss() }
    }
}

/// The end-of-day nudge. Fires once per day, only when that day is genuinely
/// missing from Whistler.
struct ReminderCard: View {
    @EnvironmentObject private var whistler: WhistlerService
    @State private var time = ""

    var body: some View {
        Card("Daily reminder") {
            HStack(spacing: 10) {
                Toggle("Remind me if the day is not logged", isOn: Binding(
                    get: { whistler.reminderEnabled },
                    set: { whistler.saveSettings(reminderEnabled: $0, reminderTime: whistler.reminderTime) }
                ))
                Spacer()
                TextField("18:00", text: $time)
                    .frame(width: 62)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .disabled(!whistler.reminderEnabled)
                    .onSubmit { commit() }
                    .onChange(of: whistler.reminderTime) { _, value in time = value }
            }
            Text("Checked every minute after the given time. It only fires when Calendar shows work that Whistler has not recorded.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { time = whistler.reminderTime }
    }

    private func commit() {
        if WhistlerService.normalizeReminderTime(time) != nil {
            whistler.saveSettings(reminderEnabled: whistler.reminderEnabled, reminderTime: time)
        } else {
            time = whistler.reminderTime
        }
    }
}

/// Month coverage: how the month is tracking against target, where the time
/// went, and which days Calendar says are still missing from Whistler.
struct WhistlerMonthCard: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var monthKey: String { String(service.todayKey.prefix(7)) }

    var body: some View {
        Card("Month coverage", accessory: AnyView(
            HStack(spacing: 8) {
                if whistler.monthStatusLoading { ProgressView().controlSize(.small) }
                Button("Refresh") { whistler.refreshMonthStatus(monthKey) }
                    .controlSize(.small)
                    .disabled(whistler.monthStatusLoading || !integrations.whistlerReady)
            }
        )) {
            if !whistler.monthStatusMessage.isEmpty {
                Label(whistler.monthStatusMessage,
                      systemImage: whistler.incompleteDays.isEmpty
                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(whistler.incompleteDays.isEmpty ? Theme.longBreak : Theme.urgent)
            }

            if whistler.monthStatusLoaded {
                let stats = whistler.monthlyStats
                HStack(spacing: 0) {
                    StatTile(label: "TARGET",
                             value: Fmt.whistlerMinutes(stats.expectedMinutes),
                             detail: "\(stats.workdayCount) workdays")
                    StatTile(label: "LOGGED",
                             value: Fmt.whistlerMinutes(stats.loggedMinutes),
                             detail: "\(stats.loggedDays) days", accented: true)
                    StatTile(label: "TO DATE",
                             value: Fmt.whistlerMinutes(stats.loggedToDateMinutes),
                             detail: "of \(Fmt.whistlerMinutes(stats.expectedToDateMinutes))")
                    StatTile(label: "BALANCE",
                             value: Fmt.whistlerSignedMinutes(stats.balanceMinutes),
                             detail: stats.balanceMinutes >= 0 ? "ahead" : "behind",
                             accented: stats.balanceMinutes >= 0)
                }

                ProgressBar(value: stats.expectedMinutes > 0
                            ? min(1, stats.loggedMinutes / stats.expectedMinutes) : 0,
                            color: Theme.focus, height: 6)

                if !whistler.projectTotals.isEmpty {
                    Divider().padding(.vertical, 2)
                    HStack(alignment: .center, spacing: 20) {
                        Chart(whistler.projectTotals) { project in
                            SectorMark(
                                angle: .value("Minutes", project.minutes),
                                innerRadius: .ratio(0.6),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Project", project.name))
                            .cornerRadius(3)
                        }
                        .frame(width: 132, height: 132)
                        .chartLegend(.hidden)
                        .chartForegroundStyleScale(range: Theme.projectColors)

                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(whistler.projectTotals.prefix(8)) { project in
                                HStack(spacing: 6) {
                                    Text(project.name).font(.caption).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(Fmt.whistlerMinutes(project.minutes))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            if whistler.projectTotals.count > 8 {
                                Text("+\(whistler.projectTotals.count - 8) more")
                                    .font(.caption2).foregroundStyle(Theme.textMuted.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider().padding(.vertical, 2)

                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                        Text(name).font(.caption2).foregroundStyle(Theme.textMuted.opacity(0.7))
                    }
                    ForEach(whistler.monthCells(monthKey, todayKey: service.todayKey)) { cell in
                        WhistlerDayCell(cell: cell, tooltip: whistler.dayTooltip(cell)) {
                            whistler.importDay(cell.key)
                        }
                    }
                }

                HStack(spacing: 14) {
                    LegendDot(color: Theme.longBreak.opacity(0.6), label: "Logged")
                    LegendDot(color: Theme.urgent.opacity(0.6), label: "Missing")
                    LegendDot(color: Theme.shortBreak.opacity(0.5), label: "Holiday")
                    Spacer()
                    Text("Right-click a day to send it").font(.caption2).foregroundStyle(Theme.textMuted.opacity(0.7))
                }
            } else if !whistler.monthStatusLoading {
                EmptyHint(text: integrations.whistlerReady
                          ? "Refresh to compare Google Calendar against Whistler for this month."
                          : "Finish the setup above to compare Calendar against Whistler.")
            }
        }
    }
}

struct WhistlerDayCell: View {
    var cell: WhistlerMonthCell
    var tooltip: String
    var onImport: () -> Void

    private var fill: Color {
        if !cell.inMonth { return .clear }
        if cell.incomplete { return Theme.urgent.opacity(0.32) }
        if cell.complete { return Theme.longBreak.opacity(0.32) }
        if cell.holiday { return Theme.shortBreak.opacity(0.2) }
        if !cell.required { return Palette.raised.opacity(0.6) }
        return Palette.raised
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(cell.isToday ? Theme.focus : .clear, lineWidth: 1.5)
            )
            .overlay(alignment: .topLeading) {
                if cell.inMonth {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(String(cell.dayNumber))
                            .font(.system(size: 10, weight: cell.isToday ? .bold : .regular).monospacedDigit())
                        if cell.loggedMinutes > 0 {
                            Text(Fmt.whistlerMinutes(cell.loggedMinutes))
                                .font(.system(size: 9).monospacedDigit())
                                .foregroundStyle(Theme.textMuted)
                        }
                    }
                    .padding(4)
                }
            }
            .frame(height: 40)
            .help(tooltip)
            .contextMenu {
                if cell.inMonth {
                    Button("Send \(cell.key) to Whistler", action: onImport)
                }
            }
    }
}

/// Free-text rules appended to the classification prompt for every event.
struct InstructionsCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = ""
    @State private var saved = false

    var body: some View {
        Card("AI mapping instructions") {
            Text("Added to the OpenRouter prompt for every event. Use it to map calendar wording onto Whistler projects.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $draft)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 130)
                .scrollContentBackground(.hidden)
                .padding(7)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Theme.border, lineWidth: 1)
                )

            HStack(spacing: 8) {
                Button("Save") {
                    whistler.saveInstructions(draft)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                .buttonStyle(.borderedProminent)
                .disabled(draft == whistler.instructionsText)

                Button("Revert") { draft = whistler.instructionsText }
                    .disabled(draft == whistler.instructionsText)
                Button("Open in editor") { state.openInstructionsInEditor() }

                if saved {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.longBreak)
                }
                Spacer()
            }
        }
        .onAppear { draft = whistler.instructionsText }
        .onChange(of: whistler.instructionsText) { _, value in
            if draft.isEmpty || saved { draft = value }
        }
    }
}
