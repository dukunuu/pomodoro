import SwiftUI
import AppKit

/// `Pomodoro --snapshot <dir>` renders the dashboard tabs to PNG files and
/// exits. This keeps UI review possible from a terminal without screen
/// recording permission, and gives the build a cheap layout smoke test.
@MainActor
enum Snapshot {
    static func requestedDirectory() -> URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"),
              index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    static func run(into directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppState.shared

        // The app follows the system appearance now, so a snapshot run has to
        // cover both: `--snapshot <dir> --light` renders the other one.
        let light = CommandLine.arguments.contains("--light")
        let appearance = NSAppearance(named: light ? .aqua : .darkAqua)!
        NSApp.appearance = appearance

        // Hosted in a window that is never ordered front, rather than drawn by
        // ImageRenderer: text fields, menus and date pickers are AppKit views,
        // which ImageRenderer replaces with a placeholder.
        func capture<V: View>(_ name: String, size: CGSize, _ view: V) {
            let hosting = NSHostingView(
                rootView: view
                    .environmentObject(state)
                    .environmentObject(state.service)
                    .environmentObject(state.whistler)
                    .environmentObject(state.integrations)
                    .environmentObject(state.updates)
                    .environmentObject(state.updateInstaller)
                    .environmentObject(state.preferences)
                    .frame(width: size.width, height: size.height)
                    .background(Theme.background)
                    .environment(\.colorScheme, light ? .light : .dark)
            )
            hosting.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            // onAppear handlers load their drafts a turn after the first layout.
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
                return
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
                return
            }
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        capture("today", size: CGSize(width: 800, height: 1260), SnapshotTab(tab: .today))
        capture("week", size: CGSize(width: 800, height: 900), SnapshotTab(tab: .week))
        capture("month", size: CGSize(width: 800, height: 760), SnapshotTab(tab: .month))
        capture("all-time", size: CGSize(width: 800, height: 860), SnapshotTab(tab: .allTime))
        capture("whistler", size: CGSize(width: 800, height: 860), SnapshotTab(tab: .whistler))
        capture("standup", size: CGSize(width: 800, height: 560), SnapshotTab(tab: .standup))
        capture("standup-replies", size: CGSize(width: 800, height: 720), SnapshotStandupReplies().padding(16))
        capture("settings", size: CGSize(width: 800, height: 980), SnapshotTab(tab: .settings))
        capture("floating", size: CGSize(width: 260, height: 120),
                FloatingTimerView(service: state.service, onOpenDashboard: {}).padding(12))
        capture("menubar", size: CGSize(width: 340, height: 590), MenuBarPanel())
        capture("sheet-whistler-config", size: CGSize(width: 640, height: 640), WhistlerConfigSheet())
        capture("sheet-whistler-account", size: CGSize(width: 640, height: 640), WhistlerConfigSheet(tab: .account))
        capture("sheet-whistler-reminder", size: CGSize(width: 640, height: 640), WhistlerConfigSheet(tab: .reminder))
        capture("sheet-standup-config", size: CGSize(width: 540, height: 380),
                StandupConfigSheet(draft: StandupDraft(), todayDate: Date()))
        capture("sheet-sign-in", size: CGSize(width: 460, height: 460), WhistlerCredentialsSheet())
        capture("sheet-api-key", size: CGSize(width: 480, height: 300), AIKeySheet(replacing: false) {})
        capture("sheet-google-client", size: CGSize(width: 480, height: 440),
                GoogleClientSheet(installError: .constant(nil)))

        exit(0)
    }
}

/// Exercises the real reply editors with credential-free, in-memory example text.
private struct SnapshotStandupReplies: View {
    @State private var yesterday = "TT-Ligla (3h 4m)\n1. Meetings (15m)\n\t- NT dev team daily standup\n\n2. Implementation (2h 49m)\n\t- Release feedback fixes\n\t- Improve cold-starts on virus scan results"
    @State private var today = "TT-Ligla\n- client meeting - meeting preparation, post meeting discussion\n- backlog refinement meeting\n\nInternal\n- ET-4 team meeting"
    @State private var yesterdayCopied = false
    @State private var todayCopied = false

    var body: some View {
        VStack(spacing: 16) {
            PageHeading(title: "Daily standup") {
                Text("0 / 2 copied").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button { } label: { Label("Refresh sources", systemImage: "arrow.clockwise") }
                    .buttonStyle(.secondary)
            }
            StandupReplyCard(title: "Yesterday", question: "What did you do yesterday?",
                             source: "Whistler · 2026-03-09 · original logged durations",
                             text: $yesterday, copied: $yesterdayCopied)
            StandupReplyCard(title: "Today", question: "What will you do today?",
                             source: "Calendar + Jira · 2026-03-10 · selected work only",
                             text: $today, copied: $todayCopied)
            Disclosure("Review today's sources and project assignments", indented: false) { EmptyView() }
            Spacer(minLength: 0)
        }
    }
}

/// Snapshot-only wrappers: the real dashboard owns its tab state, so these
/// pin one tab at a time.
private struct SnapshotTab: View {
    var tab: DashboardSection
    @State private var offset = 0

    // ImageRenderer does not rasterize ScrollView content, so the snapshot
    // lays the same cards out in a plain stack.
    var body: some View {
        VStack(spacing: 0) {
            TimerHeader()
            VStack(spacing: 16) {
                switch tab {
                case .today:
                    NoteCard()
                    DayReportView(offset: $offset)
                case .week: WeekReportView(offset: $offset)
                case .month: MonthReportView(offset: $offset)
                case .allTime: AllTimeReportView()
                case .whistler: WhistlerView()
                case .standup: StandupView(draft: StandupDraft(), today: Fmt.dateKey(Date()))
                case .settings: SettingsPanel()
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
    }
}
