import AppKit
import CryptoKit
import Foundation
import Network

/// Google's consent flow, run by the app itself: open the browser, catch the
/// redirect on a loopback port, trade the code for a refresh token, and save
/// it where the bridges read it. Nothing is printed to a console and nothing
/// has to be pasted back.
@MainActor
final class GoogleAuthorizer: ObservableObject {
    enum Stage: Equatable {
        case idle
        /// The browser is open and Google has not redirected back yet.
        case waiting
        /// The redirect arrived; the code is being exchanged.
        case finishing
        case authorized
        case failed(String)

        var isBusy: Bool { self == .waiting || self == .finishing }
    }

    @Published private(set) var stage: Stage = .idle

    /// Called once the token file has been written.
    var onAuthorized: () -> Void = {}
    /// How the consent page is shown. The app hands it to the default
    /// browser; the tests follow it themselves.
    var openURL: (URL) -> Bool = { NSWorkspace.shared.open($0) }

    static let scope = "https://www.googleapis.com/auth/calendar.events"
    private static let patience: TimeInterval = 300

    private struct Client {
        var id: String
        var secret: String
        var authURI: String
        var tokenURI: String
    }

    private struct Attempt {
        var client: Client
        var verifier: String
        var state: String
        var redirect = ""
        var consentURL: URL?
    }

    private var listener: NWListener?
    private var attempt: Attempt?
    private var generation = 0
    private var timeout: DispatchWorkItem?

    // MARK: - Flow

    func start() {
        stop()
        guard let file = DataPaths.existingGoogleClient(), let client = Self.readClient(file) else {
            stage = .failed("Install a Google OAuth client first.")
            return
        }
        generation += 1
        let current = generation
        attempt = Attempt(client: client, verifier: Self.randomToken(bytes: 48), state: Self.randomToken(bytes: 32))

        // Loopback only: the redirect comes from the browser on this Mac, and
        // a port that is not reachable from the network needs no firewall
        // prompt. Google's desktop clients accept any loopback port.
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        do {
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in self?.listenerChanged(state, generation: current) }
            }
            // Every connection is answered until the real redirect arrives:
            // browsers open speculative connections and ask for a favicon,
            // and treating the first one as the answer is what used to leave
            // the flow waiting on a URL pasted by hand.
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in self?.accept(connection, generation: current) }
            }
            self.listener = listener
            stage = .waiting
            listener.start(queue: .main)
        } catch {
            fail("Could not listen for Google's redirect: \(error.localizedDescription)")
            return
        }

        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.generation == current, self.stage == .waiting else { return }
            self.fail("Google did not send the browser back within five minutes. Try again.")
        }
        self.timeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.patience, execute: timeout)
    }

    /// Reopens the consent page of the attempt in progress.
    func reopenBrowser() {
        if let url = attempt?.consentURL { _ = openURL(url) }
    }

    func cancel() {
        stop()
        stage = .idle
    }

    /// Clears a finished attempt's message.
    func acknowledge() {
        if !stage.isBusy { stage = .idle }
    }

    private func stop() {
        generation += 1
        timeout?.cancel(); timeout = nil
        listener?.cancel(); listener = nil
        attempt = nil
    }

    private func fail(_ message: String) {
        stop()
        stage = .failed(message)
    }

    private func listenerChanged(_ state: NWListener.State, generation current: Int) {
        guard current == generation else { return }
        switch state {
        case .ready:
            guard let port = listener?.port?.rawValue, var attempt else { return }
            attempt.redirect = "http://127.0.0.1:\(port)/"
            var components = URLComponents(string: attempt.client.authURI)
            components?.queryItems = [
                URLQueryItem(name: "client_id", value: attempt.client.id),
                URLQueryItem(name: "redirect_uri", value: attempt.redirect),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scope),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "consent"),
                URLQueryItem(name: "state", value: attempt.state),
                URLQueryItem(name: "code_challenge", value: Self.challenge(for: attempt.verifier)),
                URLQueryItem(name: "code_challenge_method", value: "S256")
            ]
            guard let url = components?.url else {
                fail("The OAuth client has an invalid authorization address.")
                return
            }
            attempt.consentURL = url
            self.attempt = attempt
            if !openURL(url) { fail("Could not open the browser.") }
        case .failed(let error):
            fail("Could not listen for Google's redirect: \(error.localizedDescription)")
        default:
            break
        }
    }

    // MARK: - Redirect

    private func accept(_ connection: NWConnection, generation current: Int) {
        guard current == generation else { connection.cancel(); return }
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            Task { @MainActor in
                guard let self, current == self.generation, let attempt = self.attempt else {
                    connection.cancel()
                    return
                }
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .split(separator: "\r\n", maxSplits: 1).first.map(String.init) ?? ""
                self.answer(connection, requestLine: line, attempt: attempt, generation: current)
            }
        }
    }

    private func answer(_ connection: NWConnection, requestLine: String, attempt: Attempt, generation current: Int) {
        let parts = requestLine.split(separator: " ")
        let query = parts.count >= 2 && parts[0] == "GET"
            ? URLComponents(string: "http://127.0.0.1" + parts[1])?.queryItems ?? []
            : []
        func value(_ name: String) -> String { query.first { $0.name == name }?.value ?? "" }

        // Anything that does not carry this attempt's state is not the
        // redirect: answer it and keep waiting.
        guard !value("state").isEmpty, value("state") == attempt.state else {
            Self.send(connection, status: "404 Not Found", body: "")
            return
        }
        guard stage == .waiting else {
            Self.send(connection, status: "409 Conflict", body: "")
            return
        }
        timeout?.cancel(); timeout = nil

        if !value("error").isEmpty {
            let declined = value("error") == "access_denied"
            let message = declined ? "Access was not granted in the browser." : "Google reported: \(value("error"))."
            Self.send(connection, status: "200 OK", body: GoogleAuthorizationPage.failure(message))
            fail(message)
            return
        }
        guard !value("code").isEmpty else {
            let message = "Google sent the browser back without an authorization code."
            Self.send(connection, status: "200 OK", body: GoogleAuthorizationPage.failure(message))
            fail(message)
            return
        }

        // The tab is answered only once the token is saved, so the page it
        // shows is the real outcome.
        stage = .finishing
        let code = value("code")
        Task {
            do {
                let refreshToken = try await Self.exchange(code: code, attempt: attempt)
                guard current == self.generation else { connection.cancel(); return }
                try Self.save(refreshToken: refreshToken, clientID: attempt.client.id)
                Self.send(connection, status: "200 OK", body: GoogleAuthorizationPage.success)
                self.stop()
                self.stage = .authorized
                self.onAuthorized()
            } catch {
                guard current == self.generation else { connection.cancel(); return }
                let message = (error as? Failure)?.message ?? error.localizedDescription
                Self.send(connection, status: "200 OK", body: GoogleAuthorizationPage.failure(message))
                self.fail(message)
            }
        }
    }

    private static func send(_ connection: NWConnection, status: String, body: String) {
        let payload = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(payload.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    // MARK: - Token

    private struct Failure: Error { var message: String }

    private static func exchange(code: String, attempt: Attempt) async throws -> String {
        guard let url = URL(string: attempt.client.tokenURI) else {
            throw Failure(message: "The OAuth client has an invalid token address.")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form([
            ("code", code),
            ("client_id", attempt.client.id),
            ("client_secret", attempt.client.secret),
            ("redirect_uri", attempt.redirect),
            ("grant_type", "authorization_code"),
            ("code_verifier", attempt.verifier)
        ]).utf8)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: request)
        } catch {
            throw Failure(message: "Could not reach Google to finish authorizing: \(error.localizedDescription)")
        }
        guard let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw Failure(message: "Google's token endpoint returned an invalid response.")
        }
        if let error = result["error"] as? String {
            let detail = (result["error_description"] as? String) ?? error
            throw Failure(message: "Google authorization failed: \(detail)")
        }
        guard let refreshToken = result["refresh_token"] as? String, !refreshToken.isEmpty else {
            throw Failure(message: "Google did not return a refresh token. Try again and approve access.")
        }
        return refreshToken
    }

    /// The same file the Python flow wrote, so every bridge keeps working.
    private static func save(refreshToken: String, clientID: String) throws {
        let stored: [String: Any] = [
            "type": "authorized_user",
            "client_id": clientID,
            "refresh_token": refreshToken,
            "scopes": [scope]
        ]
        DataPaths.ensureDirectory()
        do {
            let data = try JSONSerialization.data(withJSONObject: stored, options: [.prettyPrinted, .sortedKeys])
            let temporary = DataPaths.googleToken.appendingPathExtension("tmp")
            try? FileManager.default.removeItem(at: temporary)
            guard FileManager.default.createFile(atPath: temporary.path, contents: data + Data("\n".utf8),
                                                 attributes: [.posixPermissions: 0o600]) else {
                throw Failure(message: "Could not write the Google authorization file.")
            }
            // rename(2) swaps the file in whether or not one is already there.
            guard rename(temporary.path, DataPaths.googleToken.path) == 0 else {
                throw Failure(message: "Could not save the Google authorization file.")
            }
        } catch let failure as Failure {
            throw failure
        } catch {
            throw Failure(message: "Could not save the Google authorization: \(error.localizedDescription)")
        }
    }

    // MARK: - Pieces

    private static func readClient(_ url: URL) -> Client? {
        guard let data = try? Data(contentsOf: url),
              let parsed = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let client = (parsed["installed"] ?? parsed["web"]) as? [String: Any],
              let id = client["client_id"] as? String, !id.isEmpty,
              let secret = client["client_secret"] as? String, !secret.isEmpty else { return nil }
        return Client(id: id, secret: secret,
                      authURI: (client["auth_uri"] as? String) ?? "https://accounts.google.com/o/oauth2/auth",
                      tokenURI: (client["token_uri"] as? String) ?? "https://oauth2.googleapis.com/token")
    }

    private static func randomToken(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func form(_ fields: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { name, value in
            name + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
        }.joined(separator: "&")
    }
}

/// What the browser tab shows once Google hands back: the outcome, in the
/// app's own look, and where to go next. Self-contained — no scripts, no
/// requests — because it is served from a port that closes straight after.
enum GoogleAuthorizationPage {
    static let success = page(
        ok: true,
        title: "Google Calendar is connected",
        message: "Pomodoro can now read and write your Calendar events. You can close this tab and go back to the app.")

    static func failure(_ detail: String) -> String {
        page(ok: false,
             title: "Authorization did not finish",
             message: detail + " Go back to Pomodoro and choose Authorize to try again.")
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func page(ok: Bool, title: String, message: String) -> String {
        let mark = ok
            ? "<path d=\"M7 12.5l3.2 3.2L17 9\" />"
            : "<path d=\"M8 8l8 8M16 8l-8 8\" />"
        return """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(title)) · Pomodoro</title>
        <style>
        :root { color-scheme: light dark; --bg: #ececec; --panel: #ffffff; --edge: rgba(0,0,0,.08);
                --text: #1d1d1f; --muted: #6e6e73; --ok: #5f8a55; --bad: #b4534b; --focus: #9a5f3c; }
        @media (prefers-color-scheme: dark) {
          :root { --bg: #1e1e1e; --panel: #292929; --edge: rgba(255,255,255,.08);
                  --text: #f2f2f2; --muted: #a1a1a6; --ok: #91a58b; --bad: #d39893; --focus: #b88f76; }
        }
        * { box-sizing: border-box; }
        body { margin: 0; min-height: 100vh; display: grid; place-items: center; padding: 24px;
               background: var(--bg); color: var(--text);
               font: 15px/1.5 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; }
        main { width: 100%; max-width: 420px; padding: 30px 30px 26px; text-align: center;
               background: var(--panel); border: 1px solid var(--edge); border-radius: 16px; }
        .mark { width: 52px; height: 52px; margin: 0 auto 16px; border-radius: 50%; display: grid; place-items: center;
                color: var(--tone); background: color-mix(in srgb, var(--tone) 16%, transparent); }
        .mark svg { width: 26px; height: 26px; fill: none; stroke: currentColor; stroke-width: 2.4;
                    stroke-linecap: round; stroke-linejoin: round; }
        h1 { margin: 0 0 8px; font-size: 20px; font-weight: 600; letter-spacing: -.01em; }
        p { margin: 0; color: var(--muted); }
        .app { margin-top: 22px; display: inline-flex; align-items: center; gap: 7px;
               font-size: 11px; font-weight: 600; letter-spacing: .07em; text-transform: uppercase; color: var(--muted); }
        .app i { width: 7px; height: 7px; border-radius: 50%; background: var(--focus); }
        </style>
        </head>
        <body>
        <main style="--tone: var(--\(ok ? "ok" : "bad"))">
        <div class="mark"><svg viewBox="0 0 24 24" aria-hidden="true">\(mark)</svg></div>
        <h1>\(escape(title))</h1>
        <p>\(escape(message))</p>
        <div class="app"><i></i>Pomodoro</div>
        </main>
        </body>
        </html>
        """
    }
}
