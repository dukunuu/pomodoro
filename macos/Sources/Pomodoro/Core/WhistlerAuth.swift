import Foundation

/// The two network calls the credentials form makes.
///
/// Done in-process rather than through the Python bridges so the password
/// never leaves the app: it goes straight to Whistler and what comes back is a
/// session token, which is the only part that is kept.
enum WhistlerAuth {
    struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    /// Rejects a plain-HTTP server, the way the importer does.
    static func resolveBaseURL(_ raw: String) throws -> String {
        var url = raw.trimmingCharacters(in: .whitespaces)
        while url.hasSuffix("/") { url = String(url.dropLast()) }
        guard !url.isEmpty else { throw Failure("A Whistler server is required.") }
        let local = url.contains("localhost") || url.contains("127.0.0.1")
        guard url.hasPrefix("https://") || local else {
            throw Failure("The Whistler server must use HTTPS outside localhost.")
        }
        return url
    }

    static func signIn(apiUrl: String, email: String, password: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(apiUrl)/api/auth/signin")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(
            withJSONObject: ["email": email, "password": password])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure("Whistler did not respond.")
        }
        guard http.statusCode == 200 else {
            throw Failure(http.statusCode == 401
                ? "Whistler rejected that email and password."
                : "Whistler returned HTTP \(http.statusCode).")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard let token = json?["token"] as? String, !token.isEmpty else {
            throw Failure("Whistler did not return a session token.")
        }
        return token
    }

    /// Confirms a key before it is stored, so a typo is caught at setup
    /// rather than halfway through the first import.
    static func validateOpenRouter(key: String) async throws {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/key")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw Failure("OpenRouter did not respond.")
        }
        guard http.statusCode == 200 else {
            throw Failure(http.statusCode == 401
                ? "OpenRouter rejected that API key."
                : "OpenRouter returned HTTP \(http.statusCode).")
        }
    }
}
