import Foundation

/// Where Whistler's configuration comes from: the non-secret parts from a
/// JSON file beside the history, personal secrets from Keychain, and an optional
/// distributed OpenRouter default from the bundle. Assembled
/// into the flat dictionary the Python bridges already read, so only the
/// source changed — and the secrets now reach the bridges through the child
/// process environment rather than through a file on disk.
enum WhistlerConfig {
    static let defaultApiUrl = "https://whistler.nashatech.com"
    static let mappingModel = "typesafe/jev-1.13"
    static let defaultCalendar = "primary"

    /// Carried over only for a setup migrated before it had a token.
    static let legacyPassword = "whistler-password"

    struct Settings: Equatable {
        var apiUrl: String = WhistlerConfig.defaultApiUrl
        var email: String = ""
        var calendarId: String = WhistlerConfig.defaultCalendar
    }

    private static var settingsURL: URL { DataPaths.whistlerAccount }

    static func readSettings() -> Settings {
        migrate()
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Settings()
        }
        func text(_ key: String, _ fallback: String) -> String {
            let value = json[key] as? String ?? ""
            return value.isEmpty ? fallback : value
        }
        return Settings(
            apiUrl: text("apiUrl", defaultApiUrl),
            email: text("email", ""),
            calendarId: text("calendarId", defaultCalendar))
    }

    static func writeSettings(_ settings: Settings) {
        DataPaths.ensureDirectory()
        let json: [String: Any] = [
            "version": 1,
            "apiUrl": settings.apiUrl.hasSuffix("/") ? String(settings.apiUrl.dropLast()) : settings.apiUrl,
            "email": settings.email,
            "calendarId": settings.calendarId
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: settingsURL, options: .atomic)
    }

    /// The flat shape the bridges read, secrets included. Only ever passed
    /// through a child process environment, never written out.
    static func resolve() -> [String: String] {
        let settings = readSettings()
        var values = [
            "WHISTLER_API_URL": settings.apiUrl,
            "WHISTLER_EMAIL": settings.email,
            "GOOGLE_CALENDAR_ID": settings.calendarId,
            "CALENDAR_ID": settings.calendarId,
            "OPENROUTER_MODEL": mappingModel,
            "WHISTLER_SESSION_TOKEN": SecretStore.read(SecretStore.whistlerSession) ?? "",
            "OPENROUTER_API_KEY": OpenRouterCredentials.read ?? ""
        ]
        if let password = SecretStore.read(legacyPassword), !password.isEmpty {
            values["WHISTLER_PASSWORD"] = password
        }
        return values.filter { !$0.value.isEmpty }
    }

    /// Stores what the sign-in produced. The password is never written. A nil
    /// key leaves the stored one alone, so switching accounts does not mean
    /// re-entering it.
    static func save(_ settings: Settings, sessionToken: String, openRouterKey: String?) {
        writeSettings(settings)
        SecretStore.write(SecretStore.whistlerSession, sessionToken)
        if let openRouterKey, !openRouterKey.isEmpty {
            SecretStore.write(SecretStore.openRouterKey, openRouterKey)
        }
        SecretStore.delete(legacyPassword)
    }

    /// Forgets the Whistler session and nothing else: the API key, model,
    /// calendar and instructions all survive, ready for the next account.
    static func signOut() {
        SecretStore.delete(SecretStore.whistlerSession)
        SecretStore.delete(legacyPassword)
    }

    static var isSignedIn: Bool {
        SecretStore.has(SecretStore.whistlerSession) || SecretStore.has(legacyPassword)
    }

    static func update(_ change: (inout Settings) -> Void) {
        var settings = readSettings()
        change(&settings)
        writeSettings(settings)
    }

    /// Moves a pomodoro-whistler.env into the Keychain, then scrubs and
    /// deletes it. A password is carried over only when there is no token to
    /// carry instead, so a working setup keeps working until the next sign-in
    /// replaces it.
    private static func migrate() {
        let legacy = DataPaths.whistlerConfig
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }

        let env = readEnv(legacy)
        if !env.isEmpty {
            writeSettings(Settings(
                apiUrl: env["WHISTLER_API_URL"] ?? defaultApiUrl,
                email: env["WHISTLER_EMAIL"] ?? "",
                calendarId: env["GOOGLE_CALENDAR_ID"] ?? env["CALENDAR_ID"] ?? defaultCalendar))

            SecretStore.write(SecretStore.openRouterKey, env["OPENROUTER_API_KEY"] ?? "")
            let token = env["WHISTLER_SESSION_TOKEN"] ?? ""
            if token.isEmpty {
                SecretStore.write(legacyPassword, env["WHISTLER_PASSWORD"] ?? "")
            } else {
                SecretStore.write(SecretStore.whistlerSession, token)
            }
        }

        // Overwrite before unlinking: deleting a file leaves its contents on
        // the disk, and this one held a password.
        if let size = try? FileManager.default.attributesOfItem(atPath: legacy.path)[.size] as? Int {
            try? Data(count: size).write(to: legacy)
        }
        try? FileManager.default.removeItem(at: legacy)
    }

    /// The legacy file's format, parsed here so migration does not depend on
    /// a main-actor-isolated helper.
    private static func readEnv(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"),
                  let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: separator)...])
                .trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, let last = value.last,
               first == last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            values[key] = value
        }
        return values
    }
}
