import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable, Hashable {
    case today, week, month, allTime, whistler, standup, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .week: return "Week"
        case .month: return "Month"
        case .allTime: return "All time"
        case .whistler: return "Whistler"
        case .standup: return "Daily standup"
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
        case .standup: return "text.bubble"
        case .settings: return "gearshape"
        }
    }
}

/// Lets a page send the user to another one — to where a missing piece of
/// setup lives — without owning the sidebar's selection.
private struct OpenSectionKey: EnvironmentKey {
    static let defaultValue: (DashboardSection) -> Void = { _ in }
}

extension EnvironmentValues {
    var openSection: (DashboardSection) -> Void {
        get { self[OpenSectionKey.self] }
        set { self[OpenSectionKey.self] = newValue }
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

    @StateObject private var standup = StandupDraft()
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
                    row(.standup)
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
                .environment(\.openSection) { section = $0 }
                .safeAreaInset(edge: .top, spacing: 0) {
                    // The header draws its own bottom edge: the progress line.
                    VStack(spacing: 0) {
                        TimerHeader()
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
                        Button { section = .standup } label: {
                            Label("Prepare daily standup", systemImage: "text.bubble")
                        }
                    }
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

    private var page: some View {
        ScrollView {
            // One column width for every page, settings included, so the
            // cards line up as the sidebar selection changes.
            VStack(spacing: 16) {
                reports
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.background)
    }

    @ViewBuilder private var reports: some View {
        switch section ?? .today {
        case .today:
            NoteCard()
            DayReportView(offset: $dayOffset)
        case .week:
            WeekReportView(offset: $weekOffset)
        case .month:
            MonthReportView(offset: $monthOffset)
        case .allTime:
            AllTimeReportView()
        case .whistler:
            WhistlerView()
        case .standup:
            StandupView(draft: standup, today: service.todayKey)
        case .settings:
            SettingsPanel()
        }
    }
}

/// Pick a project without typing; optional notes remain available.
struct NoteCard: View {
    var body: some View {
        Card("Working on",
             subtitle: "Pick a project to save its Calendar label automatically, or continue previous work with unnamed focus. The choice applies to this whole focus session; a note is optional.") {
            FocusEditor()
        }
    }
}

/// Shared by Today and the menu-bar popover so both edit the same session.
struct FocusEditor: View {
    var compact = false
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = ""
    @State private var selection = "continue"
    @State private var message = ""
    @FocusState private var focused: Bool

    private var dirty: Bool { draft != service.activeNote }
    private var scope: String { WhistlerMappingSettings.scope(WhistlerConfig.readSettings()) }

    private var projects: [WhistlerMappingProject] {
        whistler.mappingProjectsScope == scope ? whistler.mappingProjects : []
    }

    private var selectionTitle: String {
        switch selection {
        case "continue": return "Continue previous work"
        case "custom": return "Custom note"
        default: return projects.first { "project:" + $0.id == selection }?.name ?? "Continue previous work"
        }
    }

    private var selectionIcon: String {
        switch selection {
        case "continue": return "arrow.turn.down.right"
        case "custom": return "pencil.line"
        default: return "folder"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                MenuField(label: "Project", value: selectionTitle, icon: selectionIcon) {
                    Picker("Project", selection: Binding(get: { selection }, set: { choose($0) })) {
                        Text("Continue previous work").tag("continue")
                        Text("Custom note").tag("custom")
                        if !projects.isEmpty {
                            Divider()
                            ForEach(projects) { project in
                                Text(project.name).tag("project:" + project.id)
                            }
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .disabled(service.phase != .focus || whistler.importRunning || whistler.mappingProjectsLoading)

                Button { whistler.refreshMappingProjects() } label: {
                    if whistler.mappingProjectsLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Reload projects", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                    }
                }
                .buttonStyle(.iconFilled)
                .help("Reload projects from Whistler")
                .disabled(!WhistlerConfig.isSignedIn || whistler.mappingProjectsLoading)

                // The dashboard has the width to keep the note on the same
                // line as the project; the popover stacks it below.
                if !compact { noteField }
            }
            if !message.isEmpty { Notice(.error, message) }
            if !whistler.mappingProjectsMessage.isEmpty && !whistler.mappingProjectsLoading {
                Notice(.info, whistler.mappingProjectsMessage)
            }
            if compact { noteField }
            if compact && !WhistlerConfig.isSignedIn {
                Text("Sign in to Whistler to pick a project. Custom notes are still available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            draft = value
            syncSelection()
        }
        .onChange(of: service.phase) { _, _ in
            focused = false
            draft = service.activeNote
            syncSelection()
        }
    }

    private var noteField: some View {
        HStack(spacing: 8) {
            FieldChrome(icon: "text.alignleft", focused: focused) {
                TextField("Focus note", text: $draft, prompt: Text("What are you working on?"))
                    .focused($focused)
                    .onSubmit { saveNote() }
            }
            .disabled(service.phase != .focus)
            Button("Save", action: saveNote)
                .buttonStyle(.secondary)
                .disabled(service.phase != .focus || !dirty)
        }
    }

    private func saveNote() {
        guard service.phase == .focus else { return }
        service.saveActiveNote(draft)
        draft = service.activeNote
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
        if value == "custom" { selection = value; focused = true; return }
        do {
            var note = ""
            if value == "continue" {
                note = service.sessions
                    .filter { $0.phase == .focus && !$0.isLive && !$0.note.isEmpty }
                    .max { $0.startedAt < $1.startedAt }?.note ?? ""
            } else {
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

/// The heading a page leads with: its name, and for a dated page the
/// controls that move it. The figures follow in a `StatStrip`, so the heading
/// itself stays one line.
struct PageHeading<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: Trailing

    init(title: String, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 8)
            trailing
        }
        // Cards fill the column, so a heading that only hugs its text would
        // sit centred between them.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A page's headline figures, bare on the window the way the menu bar popover
/// sets its own: the numbers are the page, so they are not put in a box.
struct StatStrip<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            content
        }
        .controlSize(.large)
        .padding(.top, 2)
        .padding(.bottom, 8)
    }
}

/// Shared previous / label / next header used by the day, week and month tabs.
struct PeriodStepper: View {
    var title: String
    var canGoForward: Bool
    var onBack: () -> Void
    var onForward: () -> Void
    var onToday: () -> Void

    var body: some View {
        PageHeading(title: title) {
            if canGoForward {
                Button("Today", action: onToday)
                    .buttonStyle(.secondary)
            }
            // Back and forward share one well, so they read as a pair.
            HStack(spacing: 0) {
                Button(action: onBack) {
                    Label("Previous", systemImage: "chevron.left").labelStyle(.iconOnly)
                }
                .help("Previous")
                Divider().frame(height: 14)
                Button(action: onForward) {
                    Label("Next", systemImage: "chevron.right").labelStyle(.iconOnly)
                }
                .help("Next")
                .disabled(!canGoForward)
            }
            .buttonStyle(.icon)
            .background(Theme.controlFill,
                        in: RoundedRectangle(cornerRadius: Theme.controlCorner, style: .continuous))
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
            IconBadge(systemName: "arrow.down", tint: Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if case .downloading(let fraction) = installer.stage {
                    ProgressBar(value: fraction, color: Theme.accent, height: 5)
                        .frame(maxWidth: 220)
                        .padding(.top, 3)
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
                    .buttonStyle(.ghost)
                Button("Update and Restart") {
                    Task { await installer.install(update) }
                }
                .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 28)
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
