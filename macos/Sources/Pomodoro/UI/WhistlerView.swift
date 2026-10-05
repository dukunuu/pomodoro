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
        WorkCategoriesCard()
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

    private var log: URL { DataPaths.directory.appendingPathComponent("pomodoro-whistler.log") }

    private var logButton: AnyView? {
        guard FileManager.default.fileExists(atPath: log.path) else { return nil }
        return AnyView(
            Button { NSWorkspace.shared.open(log) } label: {
                Label("Open log", systemImage: "doc.text")
            }
            .buttonStyle(.ghost)
            .controlSize(.small)
        )
    }

    var body: some View {
        Card("Send to Whistler", symbol: "arrow.up.forward.app",
             subtitle: "Reads that day's Google Calendar events, classifies them, and writes the worklog.",
             accessory: logButton) {
            HStack(alignment: .center, spacing: 8) {
                DayField(day: $day)

                if !isToday {
                    Button("Today") { day = Date() }
                        .buttonStyle(.ghost)
                }
                if ready && alreadySent {
                    StatusPill(text: "Sent", tint: Theme.longBreak, systemImage: "checkmark")
                }

                Spacer(minLength: 8)

                if whistler.importRunning {
                    Button("Cancel") { whistler.cancelImport() }
                        .buttonStyle(.secondary)
                        .controlSize(.large)
                }

                Button {
                    whistler.importDay(key)
                } label: {
                    Label(whistler.importRunning ? "Sending…" : "Send \(isToday ? "today" : key)",
                          systemImage: "arrow.up.forward.app")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.primary)
                .controlSize(.large)
                .disabled(whistler.importRunning || !ready)
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            if whistler.importRunning {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressBar(value: Double(whistler.importProgress) / 100, color: Theme.accent, height: 5)
                    HStack {
                        Text(whistler.importStatus.isEmpty ? "Working…" : whistler.importStatus)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Text("\(whistler.importProgress)%").monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
                }
            } else if !whistler.importStatus.isEmpty {
                Notice(whistler.importProgress == 100 ? .success : .error, whistler.importStatus)
            }

            if !ready {
                Notice(.info, "Finish the setup above before sending.")
            } else if alreadySent && !whistler.importRunning {
                Notice(.info, "\(key) has already been sent. Sending again updates it.")
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

    private var states: [SetupState] {
        [integrations.googleClient, integrations.googleToken, integrations.whistler]
    }

    /// The step to do now: the first one that is neither done nor waiting on
    /// an earlier one. Only its button is prominent.
    private var nextStep: Int? {
        let enabled = [true, integrations.googleClient.isReady, integrations.googleToken.isReady]
        return states.indices.first { !states[$0].isReady && enabled[$0] }.map { $0 + 1 }
    }

    private var card: some View {
        let done = states.filter(\.isReady).count
        return Card("Setup", symbol: "checklist",
                    subtitle: "Whistler needs a Google Calendar client, an authorized Google account, and your Whistler credentials.",
                    accessory: AnyView(StatusPill(text: "\(done) of \(states.count) done",
                                                  tint: done == states.count ? Theme.longBreak : .secondary))) {
            VStack(spacing: 0) {
                SetupRow(
                    number: 1,
                    title: "Google OAuth client",
                    state: integrations.googleClient,
                    actionTitle: integrations.googleClient.isReady ? "Replace…" : "Install…",
                    prominent: nextStep == 1
                ) { showingGoogleHelp = true }
                RowDivider()
                SetupRow(
                    number: 2,
                    title: "Authorize Google account",
                    state: integrations.googleToken,
                    actionTitle: integrations.googleToken.isReady ? "Re-authorize" : "Authorize",
                    enabled: integrations.googleClient.isReady,
                    prominent: nextStep == 2
                ) { whistler.authorizeGoogle() }
                RowDivider()
                SetupRow(
                    number: 3,
                    title: "Whistler credentials",
                    state: integrations.whistler,
                    actionTitle: integrations.whistler.isReady ? "Reconfigure" : "Configure",
                    enabled: integrations.googleToken.isReady,
                    prominent: nextStep == 3
                ) { showingCredentials = true }
            }

            if !integrations.python.isReady {
                Notice(.error, integrations.python.detail)
            }

            if !integrations.whistlerSummary.isEmpty {
                VStack(spacing: 6) {
                    ForEach(integrations.whistlerSummary, id: \.0) { item in
                        HStack {
                            Text(item.0).font(.caption).foregroundStyle(Theme.textMuted)
                            Spacer()
                            Text(item.1).font(.caption.monospaced())
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
    var prominent: Bool = false
    var action: () -> Void

    private var tint: Color {
        switch state {
        case .ready: return Theme.longBreak
        case .blocked: return Theme.urgent
        case .missing: return .secondary
        }
    }

    /// The step number until the step is done or blocked, then its state.
    @ViewBuilder private var marker: some View {
        switch state {
        case .ready:
            IconBadge(systemName: "checkmark", tint: tint)
        case .blocked:
            IconBadge(systemName: "exclamationmark", tint: tint)
        case .missing:
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                .frame(width: 28, height: 28)
                .background((prominent ? Theme.accent : Color.secondary).opacity(0.16),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    var body: some View {
        HStack(spacing: 11) {
            marker

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(state.isReady ? AnyShapeStyle(tint) : AnyShapeStyle(.secondary))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button(actionTitle, action: action)
                .buttonStyle(AppButtonStyle(kind: prominent ? .primary : .secondary))
                .disabled(!enabled)
        }
        .padding(.vertical, 8)
        .opacity(enabled ? 1 : 0.55)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number), \(title), \(state.detail)")
    }
}

/// Explains where the client JSON comes from, then installs the chosen file.
/// This is the step that previously failed with a missing-file error.
struct GoogleClientSheet: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @Environment(\.dismiss) private var dismiss
    @Binding var installError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "key.horizontal.fill",
                        title: "Install a Google OAuth client",
                        subtitle: "The bridges sign in with your own Google Cloud OAuth client; no credentials ship with the app. Create one once:")

            VStack(alignment: .leading, spacing: 9) {
                step(1, "Open Google Cloud Console → APIs & Services → Credentials.")
                step(2, "Enable the Google Calendar API for the project.")
                step(3, "Create Credentials → OAuth client ID → Desktop app.")
                step(4, "Download the JSON, then choose it below.")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.fieldFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))

            Button {
                NSWorkspace.shared.open(URL(string: "https://console.cloud.google.com/apis/credentials")!)
            } label: {
                Label("Open Google Cloud Console", systemImage: "arrow.up.right")
            }
            .buttonStyle(.secondary)

            if let installError { Notice(.error, installError) }

            Text("It is copied to \(DataPaths.googleClient.path) and never leaves this Mac.")
                .font(.caption2)
                .foregroundStyle(Theme.textFaint)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                Button("Choose client JSON…") { chooseFile() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 480)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.accent)
                .frame(width: 18, height: 18)
                .background(Theme.accent.opacity(0.16), in: Circle())
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
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
    @FocusState private var timeFocused: Bool

    var body: some View {
        Card("Daily reminder", symbol: "bell.fill") {
            SettingRow("Remind me if the day is not logged",
                       subtitle: "Checked every minute after the given time. It only fires when Calendar shows work that Whistler has not recorded.") {
                FieldChrome(icon: "clock", focused: timeFocused) {
                    TextField("Reminder time", text: $time, prompt: Text("18:00"))
                        .font(.system(size: 13, weight: .medium).monospacedDigit())
                        .focused($timeFocused)
                        .onSubmit { commit() }
                        .onChange(of: whistler.reminderTime) { _, value in time = value }
                }
                .frame(width: 92)
                .disabled(!whistler.reminderEnabled)
                .help("24-hour time, for example 18:00")

                Switch(label: "Remind me if the day is not logged", isOn: Binding(
                    get: { whistler.reminderEnabled },
                    set: { whistler.saveSettings(reminderEnabled: $0, reminderTime: whistler.reminderTime) }
                ))
            }
        }
        .onAppear { time = whistler.reminderTime }
        .onChange(of: timeFocused) { _, focused in if !focused { commit() } }
    }

    private func commit() {
        if WhistlerService.normalizeReminderTime(time) != nil {
            guard time != whistler.reminderTime else { return }
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
        Card("Month coverage", symbol: "calendar", accessory: AnyView(
            HStack(spacing: 8) {
                if whistler.monthStatusLoading { ProgressView().controlSize(.small) }
                Button { whistler.refreshMonthStatus(monthKey) } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.secondary)
                .controlSize(.small)
                .disabled(whistler.monthStatusLoading || !integrations.whistlerReady)
            }
        )) {
            if !whistler.monthStatusMessage.isEmpty {
                Notice(whistler.incompleteDays.isEmpty ? .success : .error, whistler.monthStatusMessage)
            }

            if whistler.monthStatusLoaded {
                let stats = whistler.monthlyStats
                HStack(spacing: 10) {
                    StatTile(label: "Target",
                             value: Fmt.whistlerMinutes(stats.expectedMinutes),
                             detail: "\(stats.workdayCount) workdays",
                             symbol: "target", tint: .secondary)
                    StatTile(label: "Logged",
                             value: Fmt.whistlerMinutes(stats.loggedMinutes),
                             detail: "\(stats.loggedDays) days",
                             symbol: "checkmark.circle.fill", tint: Theme.focus)
                    StatTile(label: "To date",
                             value: Fmt.whistlerMinutes(stats.loggedToDateMinutes),
                             detail: "of \(Fmt.whistlerMinutes(stats.expectedToDateMinutes))",
                             symbol: "clock.fill", tint: Theme.shortBreak)
                    StatTile(label: "Balance",
                             value: Fmt.whistlerSignedMinutes(stats.balanceMinutes),
                             detail: stats.balanceMinutes >= 0 ? "ahead" : "behind",
                             symbol: stats.balanceMinutes >= 0 ? "arrow.up.right" : "arrow.down.right",
                             tint: stats.balanceMinutes >= 0 ? Theme.longBreak : Theme.urgent)
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

                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(whistler.projectTotals.prefix(8).enumerated()), id: \.element.id) { index, project in
                                HStack(spacing: 7) {
                                    // The chart assigns its range in data order.
                                    Circle()
                                        .fill(Theme.projectColors[index % Theme.projectColors.count])
                                        .frame(width: 7, height: 7)
                                    Text(project.name).font(.caption).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(Fmt.whistlerMinutes(project.minutes))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textMuted)
                                }
                            }
                            if whistler.projectTotals.count > 8 {
                                Text("+\(whistler.projectTotals.count - 8) more")
                                    .font(.caption2).foregroundStyle(Theme.textFaint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                Divider().padding(.vertical, 2)

                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                        Text(name).font(.caption2).foregroundStyle(Theme.textFaint)
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
                    Text("Right-click a day to send it").font(.caption2).foregroundStyle(Theme.textFaint)
                }
            } else if !whistler.monthStatusLoading {
                EmptyHint(text: integrations.whistlerReady
                          ? "Refresh to compare Google Calendar against Whistler for this month."
                          : "Finish the setup above to compare Calendar against Whistler.",
                          symbol: "calendar.badge.clock")
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
        if !cell.required { return Theme.trackFill }
        return Theme.trackFill
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
                            .font(.caption.weight(cell.isToday ? .bold : .regular).monospacedDigit())
                        if cell.loggedMinutes > 0 {
                            Text(Fmt.whistlerMinutes(cell.loggedMinutes))
                                .font(.caption2.monospacedDigit())
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

/// Plain-language preferences supplied to Jev alongside projects and Calendar context.
struct InstructionsCard: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = ""
    @State private var saved = false
    @FocusState private var editing: Bool

    private var dirty: Bool { draft != whistler.instructionsText }

    var body: some View {
        Card("Mapping instructions", symbol: "text.bubble.fill",
             subtitle: "Tell Jev how your Calendar relates to projects, what not to log, and when to use your work categories. For example: ‘Opeone to Quotomy belongs to quotomy. Don’t log Japanese club meetings.’ Unnamed focus continues previous work automatically. Calendar-type defaults apply unless overridden under Advanced.",
             accessory: dirty ? AnyView(StatusPill(text: "Unsaved", tint: Theme.accent)) : nil) {
            FieldChrome(focused: editing, padding: EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)) {
                TextEditor(text: $draft)
                    .font(Theme.mono(12))
                    .frame(minHeight: 130, idealHeight: 170, maxHeight: 320)
                    .scrollContentBackground(.hidden)
                    .focused($editing)
            }

            HStack(spacing: 8) {
                Button("Save") {
                    whistler.saveInstructions(draft)
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { saved = false }
                }
                .buttonStyle(.primary)
                .disabled(!dirty)

                Button("Revert") { draft = whistler.instructionsText }
                    .buttonStyle(.secondary)
                    .disabled(!dirty)

                if saved {
                    StatusPill(text: "Saved", tint: Theme.longBreak, systemImage: "checkmark")
                        .transition(.opacity)
                }
                Spacer()
                Button { state.openInstructionsInEditor() } label: {
                    Label("Open in editor", systemImage: "arrow.up.right")
                }
                .buttonStyle(.ghost)
            }
        }
        .onAppear { draft = whistler.instructionsText }
        .onChange(of: whistler.instructionsText) { _, value in
            if draft.isEmpty || saved { draft = value }
        }
    }
}
