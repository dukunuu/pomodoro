import Foundation

/// `Pomodoro --probe-day <YYYY-MM-DD|today|yesterday>` resolves a day exactly
/// the way the Send card does and prints the key handed to the bridge. It
/// exists to make date handling checkable without clicking through the UI.
/// `Pomodoro --status` prints what each integration still needs. Useful for
/// support, and for checking that a release's baked-in OAuth client is seen.
@MainActor
enum StatusProbe {
    static func requested() -> Bool {
        CommandLine.arguments.contains("--status")
    }

    static func run() {
        let integrations = AppState.shared.integrations
        integrations.refresh()
        func line(_ label: String, _ state: SetupState) {
            let mark = state.isReady ? "ok  " : "need"
            print("  [\(mark)] \(label): \(state.detail)")
        }
        print("data dir:      \(DataPaths.directory.path)")
        print("scripts dir:   \(DataPaths.scriptsDirectory.path)")
        print("oauth client:  \(DataPaths.existingGoogleClient()?.path ?? "none")")
        print("integrations:")
        line("python3", integrations.python)
        line("google client", integrations.googleClient)
        line("google auth", integrations.googleToken)
        line("whistler", integrations.whistler)
        print("google ready:   \(integrations.googleReady)")
        print("whistler ready: \(integrations.whistlerReady)")
        exit(0)
    }
}

@MainActor
enum SendProbe {
    static func requested() -> String? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--probe-day"),
              index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static func run(_ input: String) {
        let calendar = Fmt.calendar
        let date: Date
        switch input {
        case "today": date = Date()
        case "yesterday": date = calendar.date(byAdding: .day, value: -1, to: Date())!
        default:
            date = Fmt.dayStart(forKey: input) ?? Date()
        }
        print("input:        \(input)")
        print("resolved date: \(date)")
        print("Fmt.dateKey:   \(Fmt.dateKey(date))")
        print("timezone:      \(Fmt.calendar.timeZone.identifier)")
        print("script:        \(DataPaths.whistlerImportScript.path)")
        print("python:        \(Bridge.pythonPath)")
        print("data dir:      \(DataPaths.directory.path)")

        // Run the bridge through exactly the code path the Send button uses.
        // --dry-run means nothing is posted to Whistler.
        let key = Fmt.dateKey(date)
        print("\n--- running bridge: \(key) --dry-run ---")
        Bridge.run(DataPaths.whistlerImportScript, [key, "--dry-run"],
                   onLine: { print("out: \($0)") },
                   completion: { code, _, stderr in
            print("exit: \(code)")
            if !stderr.isEmpty { print("stderr: \(stderr)") }
            exit(code == 0 ? 0 : 1)
        })
    }
}
