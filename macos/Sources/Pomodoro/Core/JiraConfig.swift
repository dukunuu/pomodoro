import Foundation

enum JiraConfig {
    struct Settings: Codable, Equatable {
        var siteUrl = ""
        var email = ""
        var statuses = ["In Progress"]
    }

    static func read() throws -> Settings {
        guard FileManager.default.fileExists(atPath: DataPaths.jiraAccount.path) else { return Settings() }
        return try JSONDecoder().decode(Settings.self, from: Data(contentsOf: DataPaths.jiraAccount))
    }

    static func save(_ settings: Settings) throws {
        let data = try JSONEncoder().encode(settings)
        guard let text = String(data: data, encoding: .utf8), AtomicFile.write(text, to: DataPaths.jiraAccount) else {
            throw Failure("Could not save Jira settings.")
        }
    }

    static func site(_ value: String) throws -> String {
        guard let url = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme == "https", let host = url.host,
              host.range(of: "^[a-zA-Z0-9-]+\\.atlassian\\.net$", options: .regularExpression) != nil,
              url.user == nil, url.password == nil, url.port == nil,
              url.path.isEmpty || url.path == "/", url.query == nil, url.fragment == nil else {
            throw Failure("Enter a Jira Cloud site such as https://your-team.atlassian.net.")
        }
        return "https://" + host.lowercased()
    }

    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
