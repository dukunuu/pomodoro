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

/// The note attached to the focus session in progress.
struct NoteCard: View {
    @EnvironmentObject private var service: PomodoroService
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var dirty: Bool { draft != service.activeNote }

    var body: some View {
        Card("Focus note") {
            HStack(spacing: 8) {
                TextField("What are you working on?", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .focused($focused)
                    .onSubmit { service.saveActiveNote(draft) }
                    .disabled(service.phase != .focus)
                Button("Save") { service.saveActiveNote(draft) }
                    .controlSize(.large)
                    .disabled(service.phase != .focus || !dirty)
            }
            Text(service.phase == .focus
                 ? "Saved with the session when this focus phase ends."
                 : "Notes attach to focus sessions.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .onAppear { draft = service.activeNote }
        .onChange(of: service.activeNote) { _, value in
            if !focused { draft = value }
        }
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
