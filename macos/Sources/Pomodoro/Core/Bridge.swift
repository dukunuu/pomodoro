import Foundation
import AppKit

/// Runs the shared Python integration bridges. The scripts are stdlib-only and
/// already cross-platform, so the native app reuses them verbatim instead of
/// reimplementing the Google and Whistler protocols in Swift.
enum Bridge {

    /// A bundle launched from Finder inherits a minimal PATH, so a login-shell
    /// python (Homebrew, mise, pyenv) is invisible unless we look for it.
    static let pythonPath: String = {
        if let override = ProcessInfo.processInfo.environment["POMODORO_PYTHON"],
           !override.isEmpty, FileManager.default.isExecutableFile(atPath: override) {
            return override
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/share/mise/shims/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3"
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
        return "/usr/bin/python3"
    }()

    static var isAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: pythonPath)
    }

    private static func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Keep the bridges on exactly the directory the app reads and writes.
        env["POMODORO_DATA_DIR"] = DataPaths.directory.path
        env["PYTHONUNBUFFERED"] = "1"
        // Whistler's secrets reach the bridges here rather than through a
        // file. They live in the Keychain, and a child process environment is
        // the one place they can be handed over without touching the disk.
        for (key, value) in WhistlerConfig.resolve() { env[key] = value }
        return env
    }

    private static func make(_ script: URL, _ arguments: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = [script.path] + arguments
        process.environment = environment()
        process.currentDirectoryURL = DataPaths.scriptsDirectory
        return process
    }

    /// Fire-and-forget, used by the Calendar focus hooks.
    static func runDetached(_ script: URL, _ arguments: [String]) {
        guard FileManager.default.fileExists(atPath: script.path) else { return }
        let process = make(script, arguments)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { NSLog("pomodoro: bridge failed to start: \(error)") }
    }

    /// Runs a bridge, streaming stdout line by line and collecting stderr.
    /// Both callbacks are delivered on the main queue.
    @discardableResult
    static func run(_ script: URL,
                    _ arguments: [String],
                    onLine: ((String) -> Void)? = nil,
                    completion: @escaping (Int32, String, String) -> Void) -> Process? {
        guard FileManager.default.fileExists(atPath: script.path) else {
            DispatchQueue.main.async {
                completion(-1, "", "Bridge script missing: \(script.lastPathComponent)")
            }
            return nil
        }
        let process = make(script, arguments)
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let buffer = LineBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let lines = buffer.append(data)
            guard let onLine else { return }
            DispatchQueue.main.async { lines.forEach(onLine) }
        }

        var errorData = Data()
        let errorLock = NSLock()
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            errorLock.lock()
            errorData.append(data)
            errorLock.unlock()
        }

        process.terminationHandler = { finished in
            outPipe.fileHandleForReading.readabilityHandler = nil
            errPipe.fileHandleForReading.readabilityHandler = nil
            let trailing = buffer.flush()
            errorLock.lock()
            let stderrText = String(data: errorData, encoding: .utf8) ?? ""
            errorLock.unlock()
            let stdoutText = buffer.collected
            DispatchQueue.main.async {
                if let onLine { trailing.forEach(onLine) }
                completion(finished.terminationStatus, stdoutText, stderrText)
            }
        }

        NSLog("pomodoro: running %@ %@", script.lastPathComponent, arguments.joined(separator: " "))
        do {
            try process.run()
            return process
        } catch {
            DispatchQueue.main.async { completion(-1, "", "\(error)") }
            return nil
        }
    }

    /// The Google and Whistler setup flows are interactive — they print a URL
    /// and read answers from a console. Windows opens a cmd window for this;
    /// the macOS equivalent is handing Terminal a throwaway shell script.
    @discardableResult
    static func runInTerminal(_ script: URL, _ arguments: [String], title: String) -> Bool {
        guard FileManager.default.fileExists(atPath: script.path) else { return false }
        let quoted = ([pythonPath, script.path] + arguments)
            .map { "'" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            .joined(separator: " ")
        let body = """
        #!/bin/sh
        export POMODORO_DATA_DIR='\(DataPaths.directory.path)'
        cd '\(DataPaths.scriptsDirectory.path)'
        echo '=== \(title) ==='
        \(quoted)
        status=$?
        echo
        echo '=== Finished (exit '"$status"'). You can close this window. ==='
        exec /bin/sh -c 'read _ 2>/dev/null || true'
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pomodoro-\(UUID().uuidString).command")
        guard (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil else { return false }
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
        return true
    }
}

/// Splits streamed stdout into lines, the way the QML `SplitParser` did, while
/// also keeping the whole text for bridges that emit one JSON document.
private final class LineBuffer {
    private var pending = Data()
    private var text = ""
    private let lock = NSLock()

    var collected: String {
        lock.lock(); defer { lock.unlock() }
        return text
    }

    func append(_ data: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        text += String(data: data, encoding: .utf8) ?? ""
        pending.append(data)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            var line = pending.subdata(in: pending.startIndex..<newline)
            pending.removeSubrange(pending.startIndex...newline)
            if line.last == 0x0D { line.removeLast() }
            lines.append(String(data: line, encoding: .utf8) ?? "")
        }
        return lines
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        guard !pending.isEmpty else { return [] }
        var line = pending
        pending = Data()
        if line.last == 0x0D { line.removeLast() }
        return [String(data: line, encoding: .utf8) ?? ""]
    }
}
