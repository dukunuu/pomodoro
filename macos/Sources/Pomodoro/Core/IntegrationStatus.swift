import Foundation
import AppKit
import Combine

/// What each integration still needs before it can run.
///
/// The bridges fail with a bare `FileNotFoundError` when a credential file is
/// absent, which reads as a crash rather than as "you have not set this up
/// yet". The app inspects the same files up front so setup can be guided
/// instead of guessed at.
enum SetupState: Equatable {
    case ready
    case blocked(String)
    case missing(String)

    var isReady: Bool { self == .ready }

    var symbol: String {
        switch self {
        case .ready: return "checkmark.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .missing: return "circle.dashed"
        }
    }

    var detail: String {
        switch self {
        case .ready: return "Ready"
        case .blocked(let message), .missing(let message): return message
        }
    }
}

@MainActor
final class IntegrationStatus: ObservableObject {
    @Published private(set) var python: SetupState = .ready
    @Published private(set) var googleClient: SetupState = .ready
    @Published private(set) var googleToken: SetupState = .ready
    @Published private(set) var whistler: SetupState = .ready
    /// Non-secret summary of the Whistler settings, for display only.
    @Published private(set) var whistlerSummary: [(String, String)] = []

    private var watchers: [FileWatcher] = []

    init() {
        refresh()
        watchers = [DataPaths.googleClient, DataPaths.googleToken, DataPaths.whistlerAccount].map { url in
            FileWatcher(url: url) { [weak self] in self?.refresh() }
        }
    }

    var googleReady: Bool { googleClient.isReady && googleToken.isReady }
    var whistlerReady: Bool { googleReady && whistler.isReady }

    func refresh() {
        let fm = FileManager.default

        python = Bridge.isAvailable
            ? .ready
            : .blocked("No python3 found. Set POMODORO_PYTHON to an interpreter path.")

        if let url = DataPaths.existingGoogleClient() {
            googleClient = Self.validateClient(at: url)
        } else {
            googleClient = .missing("No OAuth client installed")
        }

        googleToken = fm.fileExists(atPath: DataPaths.googleToken.path)
            ? .ready
            : .missing("Not authorized yet")

        // Settings are shown; secrets are only ever reported present or
        // absent, and are never read into the UI at all.
        let settings = WhistlerConfig.readSettings()
        var summary: [(String, String)] = [
            ("Server", settings.apiUrl),
            ("Calendar", settings.calendarId),
            ("Model", settings.model)
        ]
        if !settings.email.isEmpty { summary.append(("Account", settings.email)) }
        whistlerSummary = summary

        var missing: [String] = []
        if !SecretStore.has(SecretStore.openRouterKey)
            && (ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] ?? "").isEmpty {
            missing.append("OpenRouter API key")
        }
        if !SecretStore.has(SecretStore.whistlerSession)
            && !SecretStore.has(WhistlerConfig.legacyPassword) {
            missing.append("Whistler sign-in")
        }
        switch missing.count {
        case 0: whistler = .ready
        case 2: whistler = .missing("Not configured")
        default: whistler = .blocked("Missing \(missing.joined(separator: " and "))")
        }
    }

    /// The bridges accept a Google "Desktop app" client, which serializes with
    /// either an `installed` or a `web` section.
    private static func validateClient(at url: URL) -> SetupState {
        guard let data = try? Data(contentsOf: url),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .blocked("Client file is not valid JSON")
        }
        guard let client = (parsed["installed"] ?? parsed["web"]) as? [String: Any] else {
            return .blocked("Client file has no installed/web section")
        }
        guard let id = client["client_id"] as? String, !id.isEmpty else {
            return .blocked("Client file has no client_id")
        }
        return .ready
    }

    private static func readEnv(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last,
               first == last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }

    /// Installs a client JSON the user downloaded from the Google Cloud
    /// console. Copying it into the data directory is exactly what the bridges
    /// look for, and is the step the old flow silently assumed had happened.
    /// Returns nil on success, or a message to show the user.
    func installGoogleClient(from source: URL) -> String? {
        guard let data = try? Data(contentsOf: source) else {
            return "Could not read \(source.lastPathComponent)."
        }
        guard let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let client = (parsed["installed"] ?? parsed["web"]) as? [String: Any],
              let id = client["client_id"] as? String, !id.isEmpty else {
            return "That file is not a Google OAuth client. Download the JSON for a Desktop app client."
        }
        DataPaths.ensureDirectory()
        do {
            if FileManager.default.fileExists(atPath: DataPaths.googleClient.path) {
                try FileManager.default.removeItem(at: DataPaths.googleClient)
            }
            try data.write(to: DataPaths.googleClient, options: .atomic)
        } catch {
            return "Could not install the client file: \(error.localizedDescription)"
        }
        refresh()
        return nil
    }

    func removeGoogleAuthorization() {
        try? FileManager.default.removeItem(at: DataPaths.googleToken)
        refresh()
    }
}
