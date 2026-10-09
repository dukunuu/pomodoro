import SwiftUI
import Charts
import AppKit

/// Getting the day into Whistler and seeing how the month is tracking: what
/// setup is still outstanding, the send control, then the month. How events
/// are mapped is configuration, and opens in a sheet from the send card.
struct WhistlerView: View {
    @EnvironmentObject private var integrations: IntegrationStatus

    var body: some View {
        if !integrations.whistlerReady {
            SetupChecklistCard()
        }
        SendCard()
        WhistlerMonthSection()
    }
}

/// The send control. Prominent, states its own preconditions, and reports what
/// happened rather than leaving a bridge to fail silently.
struct SendCard: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus

    @State private var day = Date()
    @State private var configuring = false

    private var key: String { Fmt.dateKey(day) }
    private var isToday: Bool { key == service.todayKey }
    private var alreadySent: Bool { whistler.isDayImported(key) }
    private var ready: Bool { integrations.whistlerReady }

    private var log: URL { DataPaths.directory.appendingPathComponent("pomodoro-whistler.log") }

    /// The two places to look when a send did not do what was expected: what
    /// it did, and the rules it followed.
    private var links: AnyView {
        AnyView(
            HStack(spacing: 6) {
                if FileManager.default.fileExists(atPath: log.path) {
                    Button { NSWorkspace.shared.open(log) } label: {
                        Label("Open log", systemImage: "doc.text")
                    }
                    .buttonStyle(.ghost)
                }
                Button { configuring = true } label: {
                    Label("Configure…", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.secondary)
                .help("Mapping rules, work categories, account and reminder")
            }
            .controlSize(.small)
        )
    }

    var body: some View {
        Card("Send to Whistler",
             subtitle: "Reads that day's Google Calendar events, classifies them, and writes the worklog.",
             accessory: links) {
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
        .sheet(isPresented: $configuring) { WhistlerConfigSheet() }
    }
}

/// Everything that shapes a send — how events are mapped, which account they
/// go to, and the end-of-day reminder — in one sheet beside the control it
/// affects, rather than on a page of its own.
struct WhistlerConfigSheet: View {
    enum Tab: Hashable { case mapping, account, reminder }

    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab
    @State private var unsaved = false
    @State private var confirmingDiscard = false

    init(tab: Tab = .mapping) { _tab = State(initialValue: tab) }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SheetHeader(symbol: "slider.horizontal.3",
                                title: "Whistler configuration",
                                subtitle: "How Calendar events become worklogs, which account sends them, and when you are reminded.")
                    Spacer(minLength: 8)
                    Button("Done") { if unsaved { confirmingDiscard = true } else { dismiss() } }
                        .buttonStyle(.primary)
                        .keyboardShortcut(.cancelAction)
                }
                SegmentedTabs(options: [(.mapping, "Mapping"), (.account, "Account"), (.reminder, "Reminder")],
                              selection: $tab)
            }
            .padding(20)

            Divider()

            // Every tab stays alive behind the one showing, so an unsaved
            // draft survives a look at another tab.
            ZStack {
                page(.mapping) {
                    InstructionsCard()
                    WorkCategoriesCard()
                }
                page(.account) {
                    WhistlerAccountSection()
                    ProjectMappingSection()
                }
                page(.reminder) {
                    ReminderCard()
                }
            }
        }
        .frame(width: 640, height: 640)
        .background(Theme.background)
        .onPreferenceChange(UnsavedChangesKey.self) { unsaved = $0 }
        .interactiveDismissDisabled(unsaved)
        .confirmationDialog("Discard unsaved changes?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { dismiss() }
        } message: {
            Text("Mapping instructions or work categories have edits that were not saved.")
        }
    }

    private func page<Content: View>(_ value: Tab, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(spacing: 16) { content() }
                .padding(20)
        }
        .opacity(tab == value ? 1 : 0)
        .allowsHitTesting(tab == value)
        .accessibilityHidden(tab != value)
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
        return Card("Setup",
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

            GoogleAuthorizationStatus(auth: whistler.googleAuth)

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

/// Where the Google consent flow stands, shown under whichever control
/// started it: the browser has the next step, so the app says it is waiting
/// and then says how it ended.
struct GoogleAuthorizationStatus: View {
    @ObservedObject var auth: GoogleAuthorizer

    var body: some View {
        switch auth.stage {
        case .idle:
            EmptyView()
        case .waiting, .finishing:
            let waiting = auth.stage == .waiting
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                VStack(alignment: .leading, spacing: 1) {
                    Text(waiting ? "Waiting for Google in your browser" : "Finishing authorization…")
                        .font(.system(size: 13, weight: .medium))
                    Text(waiting ? "Approve access there. This updates on its own when you are done."
                                 : "Saving the authorization.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if waiting {
                    Button("Open Browser Again") { auth.reopenBrowser() }
                        .buttonStyle(.ghost)
                    Button("Cancel") { auth.cancel() }
                        .buttonStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Theme.controlFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        case .authorized:
            Notice(.success, "Google Calendar is authorized.")
        case .failed(let message):
            Notice(.error, message)
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
    private var marker: some View {
        var markerTint = tint
        if case .missing = state { markerTint = prominent ? Theme.accent : .secondary }
        return Group {
            switch state {
            case .ready: Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
            case .blocked: Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold))
            case .missing: Text("\(number)").font(.system(size: 12, weight: .semibold, design: .rounded))
            }
        }
        .foregroundStyle(markerTint)
        .frame(width: 22, height: 22)
        .background(markerTint.opacity(0.16), in: Circle())
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

    var body: some View {
        Card("Daily reminder") {
            SettingRow("Remind me if the day is not logged",
                       subtitle: "Checked every minute after the given time. It only fires when Calendar shows work that Whistler has not recorded.") {
                TimeField(time: Binding(
                    get: { whistler.reminderTime },
                    set: { whistler.saveSettings(reminderEnabled: whistler.reminderEnabled, reminderTime: $0) }
                ))
                .disabled(!whistler.reminderEnabled)

                Switch(label: "Remind me if the day is not logged", isOn: Binding(
                    get: { whistler.reminderEnabled },
                    set: { whistler.saveSettings(reminderEnabled: $0, reminderTime: whistler.reminderTime) }
                ))
            }
        }
    }
}

/// The month in Whistler, laid out like the report pages: the month and its
/// headline figures, then which days are covered and where the time went.
struct WhistlerMonthSection: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var monthKey: String { String(service.todayKey.prefix(7)) }
    private var loaded: Bool { whistler.monthStatusLoaded && whistler.monthStatusKey == monthKey }

    private var title: String {
        Fmt.monthParts(monthKey).map { Fmt.monthLabel(year: $0.year, month: $0.month) } ?? "This month"
    }

    var body: some View {
        PageHeading(title: title) {
            if whistler.monthStatusLoading { ProgressView().controlSize(.small) }
            Button { whistler.refreshMonthStatus(monthKey) } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.secondary)
            .disabled(whistler.monthStatusLoading || !integrations.whistlerReady)
        }
        .padding(.top, 6)
        // Compared once on arrival rather than left blank behind a button. A
        // failed attempt leaves its message and is not retried on its own.
        .onAppear {
            if integrations.whistlerReady && !loaded && !whistler.monthStatusLoading
                && whistler.monthStatusMessage.isEmpty {
                whistler.refreshMonthStatus(monthKey)
            }
        }

        if loaded {
            let stats = whistler.monthlyStats
            VStack(spacing: 4) {
                StatStrip {
                    StatTile(label: "Target",
                             value: Fmt.whistlerMinutes(stats.expectedMinutes),
                             detail: "\(stats.workdayCount) workdays")
                    StatTile(label: "Logged",
                             value: Fmt.whistlerMinutes(stats.loggedMinutes),
                             detail: "\(stats.loggedDays) days",
                             tint: Theme.focus)
                    StatTile(label: "To date",
                             value: Fmt.whistlerMinutes(stats.loggedToDateMinutes),
                             detail: "of \(Fmt.whistlerMinutes(stats.expectedToDateMinutes))")
                    StatTile(label: "Balance",
                             value: Fmt.whistlerSignedMinutes(stats.balanceMinutes),
                             detail: stats.balanceMinutes >= 0 ? "ahead" : "behind",
                             tint: stats.balanceMinutes >= 0 ? Theme.longBreak : Theme.urgent)
                }
                ProgressBar(value: stats.expectedMinutes > 0
                            ? min(1, stats.loggedMinutes / stats.expectedMinutes) : 0,
                            color: Theme.focus, height: 5)
            }

            if !whistler.monthStatusMessage.isEmpty {
                Notice(whistler.incompleteDays.isEmpty ? .success : .error, whistler.monthStatusMessage)
            }

            Card("Days") {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { name in
                        Text(name).font(.caption2.weight(.medium)).foregroundStyle(Theme.textFaint)
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
            }

            if !whistler.projectTotals.isEmpty {
                Card("Projects") {
                    HStack(alignment: .center, spacing: 24) {
                        Chart(whistler.projectTotals) { project in
                            SectorMark(
                                angle: .value("Minutes", project.minutes),
                                innerRadius: .ratio(0.62),
                                angularInset: 1.5
                            )
                            .foregroundStyle(by: .value("Project", project.name))
                            .cornerRadius(3)
                        }
                        .frame(width: 124, height: 124)
                        .chartLegend(.hidden)
                        .chartForegroundStyleScale(range: Theme.projectColors)

                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(whistler.projectTotals.prefix(8).enumerated()), id: \.element.id) { index, project in
                                HStack(spacing: 8) {
                                    // The chart assigns its range in data order.
                                    Circle()
                                        .fill(Theme.projectColors[index % Theme.projectColors.count])
                                        .frame(width: 7, height: 7)
                                    Text(project.name).font(.system(size: 13)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(Fmt.whistlerMinutes(project.minutes))
                                        .font(.system(size: 13, weight: .medium, design: .rounded).monospacedDigit())
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
            }
        } else {
            Card {
                if whistler.monthStatusLoading {
                    EmptyHint(text: "Checking Calendar and Whistler…", symbol: "arrow.triangle.2.circlepath")
                } else {
                    EmptyHint(text: integrations.whistlerReady
                              ? "Refresh to compare Google Calendar against Whistler for this month."
                              : "Finish the setup above to compare Calendar against Whistler.",
                              symbol: "calendar.badge.clock")
                    if integrations.whistlerReady && !whistler.monthStatusMessage.isEmpty {
                        Notice(.error, whistler.monthStatusMessage)
                    }
                }
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
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .padding(.horizontal, 6)
                    .padding(.vertical, 5)
                }
            }
            .frame(height: 44)
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
        Card("Mapping instructions",
             subtitle: "Tell Jev how your Calendar relates to projects, what not to log, and when to use your work categories. For example: ‘Opeone to Quotomy belongs to quotomy. Don’t log Japanese club meetings.’ Unnamed focus continues previous work automatically. Calendar-type defaults apply unless overridden under Advanced.",
             accessory: dirty ? AnyView(StatusPill(text: "Unsaved", tint: Theme.accent)) : nil) {
            FieldChrome(focused: editing, padding: EdgeInsets(top: 8, leading: 6, bottom: 8, trailing: 6)) {
                TextEditor(text: $draft)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .frame(minHeight: 110, idealHeight: 150, maxHeight: 320)
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
        .preference(key: UnsavedChangesKey.self, value: dirty)
        .onAppear { draft = whistler.instructionsText }
        .onChange(of: whistler.instructionsText) { _, value in
            if draft.isEmpty || saved { draft = value }
        }
    }
}
