import AppKit
import SwiftUI
import Combine

/// Owns the single service instance and the app's windows. The dashboard and
/// the floating panel are plain AppKit windows hosting SwiftUI so the tray,
/// the panel, and a notification action can all raise them directly.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    let service = PomodoroService()
    let whistler = WhistlerService()
    let integrations = IntegrationStatus()
    let preferences = Preferences.shared

    private var dashboardWindow: NSWindow?
    private var floatingPanel: FloatingTimerPanel?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        service.whistler = whistler
        whistler.integrations = integrations

        service.onPhaseRing = { [weak self] finished, upcoming in
            self?.announce(finished: finished, upcoming: upcoming)
        }
        whistler.onReminder = { title, body in
            Notifier.shared.post(title: title, body: body)
        }
        Notifier.shared.onSkip = { [weak self] in
            self?.service.skip()
        }

        // Dock progress follows the phase, and the panel follows the setting.
        service.objectWillChange
            .sink { [weak self] in
                DispatchQueue.main.async { self?.refreshChrome() }
            }
            .store(in: &cancellables)
        preferences.$showFloatingTimer
            .sink { [weak self] show in
                DispatchQueue.main.async { self?.setFloatingPanel(visible: show) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Phase ring

    private func announce(finished: Phase, upcoming: Phase) {
        if preferences.playAlarmSound {
            (NSSound(named: "Glass") ?? NSSound(named: "Ping"))?.play()
        } else {
            NSSound.beep()
        }
        let title = finished == .focus ? "Focus time reached" : "Break complete"
        let body: String
        if finished == .focus {
            body = upcoming == .long
                ? "Continue working or skip when ready for a long break."
                : "Continue working or skip when ready for a short break."
        } else {
            body = "Ready for another focus session."
        }
        Notifier.shared.post(title: title, body: body, category: "phase")
        NSApp.requestUserAttention(.informationalRequest)
    }

    private func refreshChrome() {
        DockProgress.update(progress: service.phaseProgress,
                            active: service.phaseStartedAt > 0,
                            color: NSColor(Theme.color(for: service.phase)))
    }

    // MARK: - Windows

    func start() {
        Theme.applyAppearance()
        Notifier.shared.configure()
        setFloatingPanel(visible: preferences.showFloatingTimer)
        refreshChrome()
        // A menu bar app should not force a window open every launch, but it
        // must introduce itself once or a first run looks like nothing ran.
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: "hasLaunchedBefore") || !preferences.showFloatingTimer {
            defaults.set(true, forKey: "hasLaunchedBefore")
            showDashboard()
        }
    }

    func showDashboard() {
        if dashboardWindow == nil {
            let hosting = NSHostingController(
                rootView: DashboardView()
                    .environmentObject(self)
                    .environmentObject(service)
                    .environmentObject(whistler)
                    .environmentObject(integrations)
                    .environmentObject(preferences)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = "Pomodoro"
            window.setContentSize(NSSize(width: 900, height: 720))
            window.contentMinSize = NSSize(width: 720, height: 560)
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("PomodoroDashboard")
            window.center()
            dashboardWindow = window
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        dashboardWindow?.makeKeyAndOrderFront(nil)
    }

    func setFloatingPanel(visible: Bool) {
        if visible {
            if floatingPanel == nil {
                floatingPanel = FloatingTimerPanel(
                    content: FloatingTimerView(service: service) { [weak self] in
                        self?.showDashboard()
                    }
                )
            }
            floatingPanel?.orderFrontRegardless()
        } else {
            floatingPanel?.orderOut(nil)
        }
    }

    func toggleFloatingPanel() {
        preferences.showFloatingTimer.toggle()
    }

    func openDataDirectory() {
        DataPaths.ensureDirectory()
        NSWorkspace.shared.open(DataPaths.directory)
    }

    func openInstructionsInEditor() {
        if !FileManager.default.fileExists(atPath: DataPaths.whistlerInstructions.path) {
            AtomicFile.write(DataPaths.whistlerInstructionsTemplate, to: DataPaths.whistlerInstructions)
        }
        NSWorkspace.shared.open(DataPaths.whistlerInstructions)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if let directory = Snapshot.requestedDirectory() {
                Snapshot.run(into: directory)
                return
            }
            if StatusProbe.requested() {
                StatusProbe.run()
                return
            }
            if let day = SendProbe.requested() {
                SendProbe.run(day)
                return
            }
            if let file = ReportDump.requestedFile() {
                ReportDump.run(into: file)
                return
            }
            AppState.shared.start()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        MainActor.assumeIsolated { AppState.shared.showDashboard() }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
