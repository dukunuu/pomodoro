import SwiftUI

/// Whistler sign-in as a form.
///
/// Credentials used to be typed into pomodoro-whistler.env through a Terminal
/// script, which left the account password on disk in plain text beside the
/// token it had produced. Here the password is used once, in memory, and only
/// the session token is kept — in the Keychain.
///
/// The form is about the account and nothing else. The model, calendar and
/// API key each have their own row in Settings, so switching to another
/// Whistler account does not mean re-entering them. The key is asked for here
/// only when none is stored yet, because a first setup cannot send without it.
struct WhistlerCredentialsSheet: View {
    enum Purpose { case setUp, switchAccount }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var integrations: IntegrationStatus
    @EnvironmentObject private var whistler: WhistlerService

    var purpose: Purpose = .setUp
    var onSaved: () -> Void = {}

    @State private var settings = WhistlerConfig.Settings()
    @State private var previous = WhistlerConfig.Settings()
    @State private var password = ""
    @State private var openRouterKey = ""
    @State private var needsKey = false
    @State private var working = false
    @State private var failure: String?

    private var title: String {
        purpose == .switchAccount ? "Switch Whistler Account" : "Sign In to Whistler"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "person.crop.circle.fill",
                        title: title,
                        subtitle: purpose == .switchAccount && !previous.email.isEmpty
                            ? "Currently signed in as \(previous.email). Signing in replaces that session."
                            : "Your password is exchanged for a session token, then discarded.")

            VStack(alignment: .leading, spacing: 12) {
                FieldLabel("Server") {
                    InputField(label: "Server", text: $settings.apiUrl,
                               prompt: "https://whistler.example.com", icon: "server.rack")
                }
                FieldLabel("Email") {
                    InputField(label: "Email", text: $settings.email,
                               prompt: "name@company.com", icon: "envelope")
                        .textContentType(.username)
                }
                FieldLabel("Password") {
                    InputField(label: "Password", text: $password, prompt: "Password",
                               icon: "lock", secure: true, onSubmit: { if canSubmit { save() } })
                        .textContentType(.password)
                }
                if needsKey {
                    FieldLabel("OpenRouter key",
                               hint: "Classifies calendar events onto Whistler projects.") {
                        InputField(label: "OpenRouter key", text: $openRouterKey, prompt: "sk-or-…",
                                   icon: "key", secure: true, font: Theme.mono(12))
                    }
                }
            }
            .disabled(working)

            if let failure { Notice(.error, failure) }

            Text("The session token\(needsKey ? " and API key are" : " is") stored in your login Keychain, where you can inspect or revoke it.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button(working ? "Signing In…" : "Sign In") { save() }
                    .buttonStyle(.primary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(working || !canSubmit)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(working)
        .onAppear {
            previous = WhistlerConfig.readSettings()
            settings = previous
            // A different account usually means a different email; start
            // blank rather than inviting a sign-in to the one being left.
            if purpose == .switchAccount { settings.email = "" }
            needsKey = !OpenRouterCredentials.has
        }
    }

    private var canSubmit: Bool {
        !settings.email.trimmingCharacters(in: .whitespaces).isEmpty
            && !password.isEmpty
            && (!needsKey || !openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func save() {
        failure = nil
        working = true
        Task { @MainActor in
            defer { working = false }
            do {
                let url = try WhistlerAuth.resolveBaseURL(settings.apiUrl)
                let email = settings.email.trimmingCharacters(in: .whitespaces)
                guard !email.isEmpty else { throw WhistlerAuth.Failure("An email is required.") }
                guard !password.isEmpty else { throw WhistlerAuth.Failure("A password is required.") }

                var key: String?
                if needsKey {
                    let entered = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !entered.isEmpty else {
                        throw WhistlerAuth.Failure("An OpenRouter API key is required.")
                    }
                    try await WhistlerAuth.validateOpenRouter(key: entered)
                    key = entered
                }
                let token = try await WhistlerAuth.signIn(apiUrl: url, email: email, password: password)

                var saved = settings
                saved.apiUrl = url
                saved.email = email
                if saved.calendarId.isEmpty { saved.calendarId = WhistlerConfig.defaultCalendar }
                WhistlerConfig.save(saved, sessionToken: token, openRouterKey: key)

                let sameAccount = previous.email.caseInsensitiveCompare(email) == .orderedSame
                    && previous.apiUrl == url
                whistler.accountDidChange(clearImportMarkers: !previous.email.isEmpty && !sameAccount)
                integrations.refresh()

                password = ""
                openRouterKey = ""
                onSaved()
                dismiss()
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
