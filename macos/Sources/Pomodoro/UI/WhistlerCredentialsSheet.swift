import SwiftUI

/// Whistler sign-in as a form.
///
/// Credentials used to be typed into pomodoro-whistler.env through a Terminal
/// script, which left the account password on disk in plain text beside the
/// token it had produced. Here the password is used once, in memory, and only
/// the session token and the OpenRouter key are kept — in the Keychain.
struct WhistlerCredentialsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSaved: () -> Void

    @State private var settings = WhistlerConfig.Settings()
    @State private var password = ""
    @State private var openRouterKey = ""
    @State private var hasStoredKey = false
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Whistler credentials")
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

            Form {
                Section {
                    TextField("Server", text: $settings.apiUrl)
                    TextField("Email", text: $settings.email)
                    SecureField("Password", text: $password)
                } footer: {
                    Text("Exchanged for a session token, then discarded.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }

                Section {
                    SecureField(hasStoredKey ? "OpenRouter key (stored)" : "OpenRouter key",
                                text: $openRouterKey)
                    TextField("Model", text: $settings.model)
                    TextField("Calendar", text: $settings.calendarId)
                } footer: {
                    Text(hasStoredKey
                         ? "Leave the key blank to keep the one already stored."
                         : "Used to classify calendar events onto Whistler projects.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.urgent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
            }

            Text("Your password is never written to disk. The session token and the API key "
                 + "are stored in your login Keychain, where you can inspect or revoke them.")
                .font(.caption)
                .foregroundStyle(Theme.textMuted.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)

            Divider().padding(.top, 14)

            HStack(spacing: 10) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sign in and save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.focus)
                    .disabled(working)
            }
            .padding(20)
        }
        .frame(width: 460)
        .background(Theme.background)
        .onAppear {
            settings = WhistlerConfig.readSettings()
            hasStoredKey = SecretStore.has(SecretStore.openRouterKey)
        }
    }

    private func save() {
        failure = nil
        working = true
        Task {
            do {
                let url = try WhistlerAuth.resolveBaseURL(settings.apiUrl)
                let email = settings.email.trimmingCharacters(in: .whitespaces)
                guard !email.isEmpty else { throw WhistlerAuth.Failure("An email is required.") }
                guard !password.isEmpty else { throw WhistlerAuth.Failure("A password is required.") }

                let key = openRouterKey.isEmpty
                    ? (SecretStore.read(SecretStore.openRouterKey) ?? "")
                    : openRouterKey
                guard !key.isEmpty else {
                    throw WhistlerAuth.Failure("An OpenRouter API key is required.")
                }

                try await WhistlerAuth.validateOpenRouter(key: key)
                let token = try await WhistlerAuth.signIn(
                    apiUrl: url, email: email, password: password)

                var saved = settings
                saved.apiUrl = url
                saved.email = email
                if saved.model.isEmpty { saved.model = WhistlerConfig.defaultModel }
                if saved.calendarId.isEmpty { saved.calendarId = WhistlerConfig.defaultCalendar }
                WhistlerConfig.save(saved, sessionToken: token, openRouterKey: key)

                working = false
                password = ""
                onSaved()
                dismiss()
            } catch {
                working = false
                failure = error.localizedDescription
            }
        }
    }
}
