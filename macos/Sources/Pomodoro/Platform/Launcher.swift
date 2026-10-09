import AppKit
import SwiftUI

/// Own the profile before SwiftUI constructs AppState or starts any timers.
@main
struct Launcher {
    static let activateNotification = Notification.Name("com.dukunuu.pomodoro.activate")
    private static var lease: SingleInstanceLease?

    @MainActor static func main() {
        // These support tools do not construct AppState or a second timer.
        if StatusProbe.requested() { StatusProbe.run(); return }
        if let input = SendProbe.requested() {
            NSApplication.shared.setActivationPolicy(.prohibited)
            SendProbe.run(input)
            NSApplication.shared.run()
            return
        }
        let interactive = Snapshot.requestedDirectory() == nil && ReportDump.requestedFile() == nil
        // Also recognize an older installed copy that predates the lease.
        // Explicit development profiles remain isolated from the normal app.
        if ProcessInfo.processInfo.environment["POMODORO_DATA_DIR"] == nil,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: "com.dukunuu.pomodoro")
            .first(where: { $0.processIdentifier != getpid() }) {
            if !interactive { alreadyRunning() }
            existing.activate(options: [])
            activatePrimary()
            return
        }
        do {
            lease = try SingleInstanceLease.acquire(at: DataPaths.directory.appendingPathComponent(".pomodoro-app.lock"))
            guard lease != nil else {
                if !interactive { alreadyRunning() }
                activatePrimary()
                return
            }
        } catch {
            FileHandle.standardError.write(Data("Could not acquire Pomodoro's instance lock: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
        PomodoroApp.main()
    }

    private static func activatePrimary() {
        DistributedNotificationCenter.default().postNotificationName(activateNotification,
            object: DataPaths.directory.path, userInfo: nil, deliverImmediately: true)
    }

    private static func alreadyRunning() -> Never {
        FileHandle.standardError.write(Data("Pomodoro is already running for this data directory. Use an isolated POMODORO_DATA_DIR for snapshots or report dumps.\n".utf8))
        exit(1)
    }
}
