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
        Theme.applyAppearance()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let state = AppState.shared

        func capture<V: View>(_ name: String, size: CGSize, _ view: V) {
            let renderer = ImageRenderer(
                content: view
                    .environmentObject(state)
                    .environmentObject(state.service)
                    .environmentObject(state.whistler)
                    .environmentObject(state.integrations)
                    .environmentObject(state.preferences)
                    .frame(width: size.width, height: size.height)
                    .background(Theme.background)
                    .environment(\.colorScheme, .dark)
                    .tint(Theme.focus)
            )
            renderer.scale = 2
            guard let image = renderer.nsImage,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else {
                FileHandle.standardError.write(Data("snapshot failed: \(name)\n".utf8))
                return
            }
            try? png.write(to: directory.appendingPathComponent("\(name).png"))
            print("wrote \(name).png")
        }

        capture("today", size: CGSize(width: 800, height: 940), SnapshotTab(tab: .today))
        capture("week", size: CGSize(width: 800, height: 760), SnapshotTab(tab: .week))
        capture("month", size: CGSize(width: 800, height: 700), SnapshotTab(tab: .month))
        capture("all-time", size: CGSize(width: 800, height: 760), SnapshotTab(tab: .allTime))
        capture("whistler", size: CGSize(width: 800, height: 900), SnapshotTab(tab: .whistler))
        capture("settings", size: CGSize(width: 800, height: 760), SnapshotTab(tab: .settings))
        capture("floating", size: CGSize(width: 260, height: 120),
                FloatingTimerView(service: state.service, onOpenDashboard: {}).padding(12))
        capture("menubar", size: CGSize(width: 300, height: 430), MenuBarPanel())

        exit(0)
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
            Divider()
            VStack(spacing: 14) {
                switch tab {
                case .today:
                    NoteCard()
                    QuickStatsRow()
                    DayReportView(offset: $offset)
                case .week: WeekReportView(offset: $offset)
                case .month: MonthReportView(offset: $offset)
                case .allTime: AllTimeReportView()
                case .whistler: WhistlerView()
                case .settings: SettingsPanel()
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
    }
}
