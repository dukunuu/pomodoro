import Foundation

/// On-disk locations shared with the Python bridges.
///
/// The directory and the JSON shapes are inherited from the QML service this
/// app was ported from — `QStandardPaths::AppLocalDataLocation` for the
/// organization "Dukunuu" and application "Pomodoro". They are kept as-is so
/// an existing history loads without a migration.
enum DataPaths {
    static let directory: URL = {
        if let override = ProcessInfo.processInfo.environment["POMODORO_DATA_DIR"],
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Dukunuu/Pomodoro", isDirectory: true)
    }()

    static var state: URL { directory.appendingPathComponent("pomodoro.json") }
    static var history: URL { directory.appendingPathComponent("pomodoro-history.json") }
    static var whistlerSettings: URL { directory.appendingPathComponent("pomodoro-whistler-settings.json") }
    static var whistlerInstructions: URL { directory.appendingPathComponent("pomodoro-whistler-instructions.txt") }
    static var whistlerImportState: URL { directory.appendingPathComponent("pomodoro-whistler-imports.json") }
    static var whistlerConfig: URL { directory.appendingPathComponent("pomodoro-whistler.env") }
    static var integrationsConfig: URL { directory.appendingPathComponent("pomodoro-integrations.env") }
    static var googleClient: URL { directory.appendingPathComponent("google-calendar-client.json") }
    static var googleToken: URL { directory.appendingPathComponent("pomodoro-google-token.json") }

    /// pomodoro_paths.py prefers a per-user client file and falls back to one
    /// bundled beside the scripts; mirror that lookup so the app reports the
    /// file the bridges will actually load.
    static func existingGoogleClient() -> URL? {
        let bundled = script("google-calendar-client.json")
        if FileManager.default.fileExists(atPath: googleClient.path) { return googleClient }
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return nil
    }

    static let whistlerInstructionsTemplate = """
    # Optional instructions for project and client mapping.
    # This text is added to the AI classification prompt.
    # Example: Events containing Eventomy are work for the Whistler project Quotomy.
    # Remove the # characters and add your own rules.

    """

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// The Python bridges are copied into the bundle's Resources by
    /// build-macos.sh, and can be overridden for development.
    static let scriptsDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["POMODORO_SCRIPT_DIR"],
           !override.trimmingCharacters(in: .whitespaces).isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        if let resource = Bundle.main.resourceURL {
            let bundled = resource.appendingPathComponent("scripts", isDirectory: true)
            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }
        return URL(fileURLWithPath: Bundle.main.bundlePath)
            .deletingLastPathComponent()
            .appendingPathComponent("scripts", isDirectory: true)
    }()

    static func script(_ name: String) -> URL {
        scriptsDirectory.appendingPathComponent(name)
    }

    static var integrationsScript: URL { script("pomodoro_integrations.py") }
    static var googleAuthScript: URL { script("pomodoro_google_auth.py") }
    static var whistlerSetupScript: URL { script("pomodoro_whistler_setup.py") }
    static var whistlerImportScript: URL { script("pomodoro_whistler_import.py") }
}
