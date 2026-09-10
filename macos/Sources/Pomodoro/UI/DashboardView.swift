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
            List(selection: $section) {
                Section("Reports") {
                    row(.today); row(.week); row(.month); row(.allTime)
                }
                Section("Integrations") {
                    row(.whistler, badge: integrations.whistlerReady ? nil : "!")
                }
                Section {
                    row(.settings)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Palette.black)
            .navigationSplitViewColumnWidth(min: 168, ideal: 186, max: 240)
        } detail: {
            VStack(spacing: 0) {
                TimerHeader()
                Divider()
                ScrollView {
                    // One column width for every page. Reports used to run to
                    // the window edge while settings sat in a narrow column,
                    // so the two halves of the app never lined up.
                    VStack(spacing: 14) {
                        if let update = updates.available { UpdateBanner(update: update) }
                        content
                    }
                    .padding(16)
                    .frame(maxWidth: 880)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .background(Theme.background)
            }
            .navigationTitle(section?.title ?? "Pomodoro")
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
        .frame(minWidth: 860, minHeight: 600)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .tint(Theme.focus)
    }

    private func row(_ item: DashboardSection, badge: String? = nil) -> some View {
        Label(item.title, systemImage: item.symbol)
            .badge(badge ?? "")
            .tag(item)
    }

    @ViewBuilder private var content: some View {
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
            SettingsPanel()
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
        Card("What are you focusing on?") {
            HStack(spacing: 8) {
                TextField("Add a note for this session", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit { service.saveActiveNote(draft) }
                    .disabled(service.phase != .focus)
                Button("Save") { service.saveActiveNote(draft) }
                    .disabled(service.phase != .focus || !dirty)
            }
            Text(service.phase == .focus
                 ? "Saved with the session when this focus phase ends."
                 : "Notes attach to focus sessions.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.7))
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
                StatTile(label: "FOCUS", value: stats.focusText, detail: "active time", accented: true)
                Divider().frame(height: 34)
                StatTile(label: "BREAKS", value: stats.breakText, detail: "\(stats.breaks) taken")
                    .padding(.leading, 14)
                Divider().frame(height: 34)
                StatTile(label: "SESSIONS", value: String(stats.sessions), detail: "completed", accented: true)
                    .padding(.leading, 14)
                Divider().frame(height: 34)
                StatTile(label: "PHASES", value: String(stats.phases), detail: "recorded")
                    .padding(.leading, 14)
            }
        }
    }
}

/// Shared previous / label / next header used by the day, week and month tabs.
/// The heading a page leads with. Sits above the cards rather than inside the
/// first one, so every card on every page carries the same small uppercase
/// label and nothing competes with it.
struct PageHeading: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.headline).foregroundStyle(Theme.textBright)
            Text(subtitle).font(.caption).foregroundStyle(Theme.textMuted)
        }
        // Cards fill the column, so a heading that only hugs its text would
        // sit centred between them.
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PeriodStepper: View {
    var title: String
    var subtitle: String
    var canGoForward: Bool
    var onBack: () -> Void
    var onForward: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            PageHeading(title: title, subtitle: subtitle)
            Spacer()
            Button("Today", action: onToday)
                .buttonStyle(.borderless)
                .font(.caption)
            HStack(spacing: 0) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                Button(action: onForward) { Image(systemName: "chevron.right") }
                    .disabled(!canGoForward)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
                .foregroundStyle(Theme.focus)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(Theme.textBright)
                if case .downloading(let fraction) = installer.stage {
                    ProgressBar(value: fraction, color: Theme.focus, height: 3)
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
                Button("Update and restart") {
                    Task { await installer.install(update) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.focus)
                Button("Release notes") { openURL(update.pageURL) }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(Theme.focus.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.cardCorner))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardCorner)
                .strokeBorder(Theme.focus.opacity(0.45), lineWidth: 1)
        )
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
        return Theme.textMuted
    }
}
