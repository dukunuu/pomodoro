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
                    VStack(spacing: 14) {
                        content
                    }
                    .padding(16)
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
        Card {
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
struct PeriodStepper: View {
    var title: String
    var subtitle: String
    var canGoForward: Bool
    var onBack: () -> Void
    var onForward: () -> Void
    var onToday: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.headline).foregroundStyle(Theme.textBright)
                Text(subtitle).font(.caption).foregroundStyle(Theme.textMuted)
            }
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
