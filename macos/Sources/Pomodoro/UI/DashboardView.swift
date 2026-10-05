import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case today, week, month, allTime, whistler, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .allTime: return "All time"
        case .whistler: return "Whistler"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "sun.max"
        case .week: return "calendar.day.timeline.left"
        case .month: return "calendar"
        case .allTime: return "chart.bar.xaxis"
        case .whistler: return "arrow.up.forward.app"
        case .settings: return "gearshape"
        }
    }
}

/// Sidebar plus a pinned timer. The timer is the app; every section is a
/// different reading of it, so it stays on screen rather than scrolling away.
struct DashboardView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @EnvironmentObject private var integrations: IntegrationStatus
    @EnvironmentObject private var updates: UpdateChecker

    @State private var section: DashboardSection? = .today
    @State private var dayOffset = 0
    @State private var weekOffset = 0
    @State private var monthOffset = 0

    var body: some View {
        NavigationSplitView {
            // No background of its own: the sidebar's vibrancy is the system's
            // to draw, and it carries the window's material under the
            // transparent title bar.
            List(selection: $section) {
                Section("Reports") {
                    row(.today); row(.week); row(.month); row(.allTime)
                }
                Section("Integrations") {
                    row(.whistler, warning: !integrations.whistlerReady)
                }
                Section {
                    row(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 176, ideal: 196, max: 260)
        } detail: {
            // The timer is pinned as a safe-area inset rather than stacked
            // above the page: that is what tells the page's scroll view how
            // much room is already taken, so a grouped Form starts below the
            // header instead of under it.
            page
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                        TimerHeader()
                        Divider()
                        if let update = updates.available {
                            UpdateBanner(update: update)
                            Divider()
                        }
                    }
                }
                .navigationTitle(section?.title ?? "Pomodoro")
                .onChange(of: section, initial: true) { _, value in
                    state.setDashboardTitle(value?.title ?? "Pomodoro")
                }
                .toolbar {
                    ToolbarItem {
                        Button {
                            section = .whistler
                            whistler.importDay(service.todayKey)
                        } label: {
                            Label("Send today to Whistler", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(whistler.importRunning || !integrations.whistlerReady)
                        .help(integrations.whistlerReady
                              ? "Send today's Calendar events to Whistler"
                              : "Finish the Whistler setup first")
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 620)
    }

    private func row(_ item: DashboardSection, warning: Bool = false) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(warning ? Text(Image(systemName: "exclamationmark.triangle.fill")) : nil)
            .tag(item)
    }

    /// Settings scrolls itself — a grouped Form is a scroll view already — so
    /// only the report pages get the shared column.
    @ViewBuilder private var page: some View {
        switch section ?? .today {
        case .settings:
            SettingsPanel()
        default:
            ScrollView {
                // One column width for every page. Reports used to run to
                // the window edge while settings sat in a narrow column,
                // so the two halves of the app never lined up.
                VStack(spacing: 18) {
                    reports
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background(Theme.background)
        }
    }

    @ViewBuilder private var reports: some View {
        switch section ?? .today {
        case .today:
            NoteCard()
            QuickStatsRow()
            DayReportView(offset: $dayOffset)
        case .week:
            WeekReportView(offset: $weekOffset)
        case .month:
            MonthReportView(offset: $monthOffset)
        case .allTime:
            AllTimeReportView()
        case .whistler:
            WhistlerView()
        case .settings:
            EmptyView()
        }
    }
}

/// Pick a project without typing; optional notes remain available.
struct NoteCard: View {
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = ""
    @State private var selection = "continue"
    @State private var noteExpanded = false
    @State private var message = ""
    @FocusState private var focused: Bool

    private var dirty: Bool { draft != service.activeNote }
    private var scope: String { WhistlerMappingSettings.scope(WhistlerConfig.readSettings()) }

    var body: some View {
        Card("Focus") {
            HStack(spacing: 8) {
                Picker("Project", selection: Binding(get: { selection }, set: { choose($0) })) {
                    Text("Continue previous work").tag("continue")
                    Text("Custom note").tag("custom")
                    if whistler.mappingProjectsScope == scope {
                        ForEach(whistler.mappingProjects) { project in
                            Text(project.name).tag("project:" + project.id)
                        }
                    }
                }
                .disabled(service.phase != .focus || whistler.importRunning || whistler.mappingProjectsLoading)
                Button(whistler.mappingProjectsLoading ? "Loading…" : "Reload projects") {
                    whistler.refreshMappingProjects()
                }.disabled(!WhistlerConfig.isSignedIn || whistler.mappingProjectsLoading)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(Theme.urgent) }
            if !whistler.mappingProjectsMessage.isEmpty {
                Text(whistler.mappingProjectsMessage).font(.caption).foregroundStyle(Theme.textMuted)
            }
            DisclosureGroup("Optional focus note", isExpanded: $noteExpanded) {
                HStack(spacing: 8) {
                    TextField("What are you working on?", text: $draft)
                        .textFieldStyle(.roundedBorder).controlSize(.large).focused($focused)
                        .onSubmit { service.saveActiveNote(draft) }
                        .disabled(service.phase != .focus)
                    Button("Save") { service.saveActiveNote(draft) }
                        .disabled(service.phase != .focus || !dirty)
                }
            }
            Text("Pick a project to save its Calendar label automatically, or continue previous work with unnamed focus. The choice applies to this whole focus session; a note is optional.")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .onAppear {
            draft = service.activeNote
            syncSelection()
            if WhistlerConfig.isSignedIn && whistler.mappingProjectsScope != scope { whistler.refreshMappingProjects() }
        }
        .onChange(of: scope) { _, _ in
            message = ""
            syncSelection()
            if WhistlerConfig.isSignedIn { whistler.refreshMappingProjects() }
        }
        .onChange(of: whistler.mappingProjects) { _, _ in syncSelection() }
        .onChange(of: service.activeNote) { _, value in
            if !focused { draft = value }
            syncSelection()
        }
    }

    private func syncSelection() {
        if service.activeNote.isEmpty { selection = "continue"; return }
        let aliases = (try? WhistlerMappingSettings.read().projectAliases[scope]) ?? []
        if whistler.mappingProjectsScope == scope,
           let alias = aliases.first(where: {
               WhistlerMappingSettings.normalized(service.activeNote).hasPrefix("[" + WhistlerMappingSettings.normalized($0.alias) + "]")
           }),
           whistler.mappingProjects.contains(where: { $0.id == alias.projectId }) {
            selection = "project:" + alias.projectId
        } else { selection = "custom" }
    }

    private func choose(_ value: String) {
        guard service.phase == .focus, !whistler.importRunning else { return }
        if value == "custom" { selection = value; noteExpanded = true; focused = true; return }
        do {
            var note = ""
            if value != "continue" {
                guard whistler.mappingProjectsScope == scope,
                      let project = whistler.mappingProjects.first(where: { "project:" + $0.id == value }) else {
                    throw WhistlerMappingSettings.Failure.invalid("Reload projects for the current account.")
                }
                var settings = try WhistlerMappingSettings.read()
                note = try FocusProjectSelection.select(projectId: project.id, name: project.name, scope: scope, settings: &settings)
                try settings.save()
                whistler.mappingDidChange()
            }
            focused = false
            draft = note
            service.saveActiveNote(note)
            selection = value
            message = ""
        } catch { message = error.localizedDescription }
    }
}

/// Today at a glance, as one card rather than three competing ones.
struct QuickStatsRow: View {
    @EnvironmentObject private var service: PomodoroService

    var body: some View {
        let stats = service.statsForDay(service.todayKey)
        Card("Today") {
            HStack(spacing: 0) {
                StatTile(label: "Focus", value: stats.focusText, detail: "active time", accented: true)
                Divider().frame(height: 38)
                StatTile(label: "Breaks", value: stats.breakText, detail: "\(stats.breaks) taken")
                    .padding(.leading, 16)
                Divider().frame(height: 38)
                StatTile(label: "Sessions", value: String(stats.sessions), detail: "completed", accented: true)
                    .padding(.leading, 16)
                Divider().frame(height: 38)
                StatTile(label: "Phases", value: String(stats.phases), detail: "recorded")
                    .padding(.leading, 16)
            }
        }
    }
}

/// The heading a page leads with. Sits above the cards rather than inside the
/// first one, so every card on every page carries the same section label and
/// nothing competes with it.
struct PageHeading: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2.weight(.semibold))
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        // Cards fill the column, so a heading that only hugs its text would
        // sit centred between them.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared previous / label / next header used by the day, week and month tabs.
struct PeriodStepper: View {
    var title: String
    var subtitle: String
    var canGoForward: Bool
    var onBack: () -> Void
    var onForward: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PageHeading(title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            Button("Today", action: onToday)
            // The paired chevrons AppKit uses for stepping a date range.
            ControlGroup {
                Button(action: onBack) {
                    Label("Previous", systemImage: "chevron.left")
                }
                Button(action: onForward) {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(!canGoForward)
            }
            .controlGroupStyle(.navigation)
            .fixedSize()
        }
    }
}

/// Shown once a newer release exists. Downloading stays a click: the app
/// writes files the other front ends read, so it never swaps itself out from
/// under a running timer.
struct UpdateBanner: View {
    var update: AvailableUpdate
    @EnvironmentObject private var installer: UpdateInstaller
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.title3)
                .foregroundStyle(.white, Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if case .downloading(let fraction) = installer.stage {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 220)
                } else {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(subtitleColor)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if !installer.stage.isBusy {
                Button("Release notes") { openURL(update.pageURL) }
                Button("Update and Restart") {
                    Task { await installer.install(update) }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // A notification bar below the toolbar, in the system's own register
        // rather than a tinted slab of its own.
        .background(.bar)
    }

    private var title: String {
        switch installer.stage {
        case .downloading: return "Downloading \(update.version)…"
        case .verifying: return "Verifying \(update.version)…"
        case .installing: return "Installing \(update.version)…"
        case .failed: return "Update failed"
        case .idle: return "Version \(update.version) is available"
        }
    }

    private var subtitle: String {
        if case .failed(let message) = installer.stage { return message }
        return update.name
    }

    private var subtitleColor: Color {
        if case .failed = installer.stage { return Theme.urgent }
        return .secondary
    }
}
