import SwiftUI

// Account, Calendar, and project-mapping settings. The decision engine is fixed to Jev.
struct WhistlerAccountSection: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @EnvironmentObject private var whistler: WhistlerService
    @State private var settings = WhistlerConfig.Settings()
    @State private var signedIn = false
    @State private var calendar = ""
    @State private var showingSignIn = false
    @State private var confirmingSignOut = false
    @FocusState private var calendarFocused: Bool

    private var host: String { URL(string: settings.apiUrl)?.host ?? settings.apiUrl }

    var body: some View {
        Card("Whistler account",
             subtitle: "Signing out removes only the Whistler session from Keychain. Your API key and mapping instructions are kept.",
             accessory: AnyView(StatusPill(text: signedIn ? "Signed in" : "Signed out",
                                           tint: signedIn ? Theme.longBreak : .secondary,
                                           systemImage: signedIn ? "checkmark" : nil))) {
            VStack(spacing: 9) {
                SettingRow(signedIn ? (settings.email.isEmpty ? "Signed in" : settings.email) : "Not signed in",
                           subtitle: signedIn ? host : "Sign in to send worklogs to Whistler.") {
                    if signedIn {
                        Button("Sign Out…") { confirmingSignOut = true }.buttonStyle(.destructive)
                        Button("Switch Account…") { showingSignIn = true }.buttonStyle(.secondary)
                    } else {
                        Button("Sign In…") { showingSignIn = true }.buttonStyle(.primary)
                    }
                }
                RowDivider()
                SettingRow("Google account",
                           subtitle: integrations.googleToken.isReady
                               ? "Authorized to read and write Calendar events."
                               : integrations.googleToken.detail) {
                    Button(integrations.googleToken.isReady ? "Re-authorize" : "Authorize") {
                        whistler.authorizeGoogle()
                    }
                    .buttonStyle(AppButtonStyle(kind: integrations.googleToken.isReady ? .secondary : .primary))
                    .disabled(!integrations.googleClient.isReady)
                }
                GoogleAuthorizationStatus(auth: whistler.googleAuth)
                RowDivider()
                SettingRow("Google calendar",
                           subtitle: "“primary”, or a calendar ID from Google Calendar settings.") {
                    FieldChrome(focused: calendarFocused) {
                        TextField("Google calendar", text: $calendar, prompt: Text(WhistlerConfig.defaultCalendar))
                            .font(.system(size: 13))
                            .focused($calendarFocused)
                            .onSubmit(saveCalendar)
                    }
                    .frame(width: 240)
                }
            }
        }
        .onAppear(perform: load)
        .onChange(of: integrations.whistler) { _, _ in load() }
        .onChange(of: calendarFocused) { _, focused in if !focused { saveCalendar() } }
        .confirmationDialog("Sign out of Whistler?", isPresented: $confirmingSignOut) {
            Button("Sign Out", role: .destructive, action: signOut)
        } message: {
            Text("Sending stops until you sign in again. Nothing already in Whistler is changed.")
        }
        .sheet(isPresented: $showingSignIn) {
            WhistlerCredentialsSheet(purpose: signedIn ? .switchAccount : .setUp, onSaved: load)
        }
    }

    private func load() {
        settings = WhistlerConfig.readSettings()
        signedIn = WhistlerConfig.isSignedIn
        if !calendarFocused { calendar = settings.calendarId }
    }

    private func saveCalendar() {
        let value = calendar.trimmingCharacters(in: .whitespaces)
        let resolved = value.isEmpty ? WhistlerConfig.defaultCalendar : value
        calendar = resolved
        guard resolved != settings.calendarId else { return }
        WhistlerConfig.update { $0.calendarId = resolved }
        whistler.accountDidChange(clearImportMarkers: false)
        integrations.refresh()
        load()
    }

    private func signOut() {
        WhistlerConfig.signOut()
        whistler.accountDidChange(clearImportMarkers: false)
        integrations.refresh()
        load()
    }
}

struct ProjectMappingSection: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @State private var keySource: OpenRouterCredentials.Source = .missing
    @State private var fallbackSource: OpenRouterCredentials.Source = .missing
    @State private var showingKey = false
    @State private var confirmingKeyRemoval = false
    @State private var keyMessage: String?
    @State private var keyRemovalFailed = false
    private var hasStoredKey: Bool { keySource == .stored }
    private var hasKey: Bool { keySource != .missing }
    private var keyDescription: String {
        switch keySource {
        case .stored: "Stored in Keychain"
        case .environment: "Provided by environment"
        case .bundled: "Provided by this build — shared key"
        case .missing: "Not set — sending is unavailable"
        }
    }

    private var removeKeyAction: String {
        switch fallbackSource {
        case .bundled: "Use Built-in Key…"
        case .environment: "Use Environment Key…"
        default: "Remove Key…"
        }
    }

    private var removalMessage: String {
        let fallback = switch fallbackSource {
        case .bundled: "Pomodoro will use the built-in shared key."
        case .environment: "Pomodoro will use OPENROUTER_API_KEY from the environment."
        default: "This build has no default key. Sending will be unavailable until you add another key."
        }
        return "Your personal key will be removed from Keychain. \(fallback) Your Whistler sign-in and mapping settings are kept. This does not revoke the key on OpenRouter."
    }

    var body: some View {
        Card("Project mapping",
             subtitle: "Jev maps Calendar events to your Whistler projects using your aliases and skip rules. Configure those in Whistler. Hours and worklog text are assembled locally; there is no model to choose.") {
            SettingRow("Mapping engine", subtitle: "Fixed for every send.") {
                StatusPill(text: "Jev", tint: Theme.accent)
            }
            if hasKey && !hasStoredKey {
                Disclosure("Advanced") { apiKeyConfiguration }
            } else {
                RowDivider()
                apiKeyConfiguration
            }
            if let keyMessage { Notice(keyRemovalFailed ? .error : .success, keyMessage) }
        }
        .onAppear(perform: load)
        .onChange(of: integrations.whistler) { _, _ in load() }
        .confirmationDialog("Remove personal API key?", isPresented: $confirmingKeyRemoval, titleVisibility: .visible) {
            Button("Remove Personal Key", role: .destructive, action: removeKey)
        } message: {
            Text(removalMessage)
        }
        .sheet(isPresented: $showingKey) {
            AIKeySheet(replacing: hasStoredKey) { keyMessage = nil; integrations.refresh(); load() }
        }
    }

    private var apiKeyConfiguration: some View {
        SettingRow(hasKey ? "Personal API key override" : "OpenRouter API key",
                   subtitle: keyDescription,
                   dot: hasKey ? nil : Theme.urgent) {
            if hasStoredKey {
                Button(removeKeyAction) { confirmingKeyRemoval = true }
                    .buttonStyle(.secondary)
            }
            Button(hasStoredKey ? "Replace Key…" : hasKey ? "Use Own Key…" : "Add Key…") { showingKey = true }
                .buttonStyle(AppButtonStyle(kind: hasKey ? .secondary : .primary))
        }
    }

    private func load() {
        keySource = OpenRouterCredentials.source
        fallbackSource = OpenRouterCredentials.fallbackSource
    }

    private func removeKey() {
        keyRemovalFailed = !OpenRouterCredentials.removeStoredKey()
        integrations.refresh()
        load()
        if keyRemovalFailed {
            keyMessage = "Could not remove the personal key from Keychain. Unlock your login Keychain and try again."
        } else {
            keyMessage = switch keySource {
            case .bundled: "Personal API key removed. Using the built-in shared key."
            case .environment: "Personal API key removed. Using the environment key."
            default: "Personal API key removed. Add a key to send worklogs."
            }
        }
    }
}

/// Optional personal override; never changes the fixed mapping engine or Whistler session.
struct AIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    var replacing: Bool
    var onSaved: () -> Void
    @State private var key = ""
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "key.fill",
                        title: replacing ? "Replace API Key" : "Add API Key",
                        subtitle: "Enter an OpenRouter key. It is checked with OpenRouter before it \(replacing ? "replaces your current key" : "is stored") in the login Keychain. Your Whistler sign-in and mapping rules are not changed.")
            FieldLabel("OpenRouter API key") {
                InputField(label: "OpenRouter API key", text: $key, prompt: "sk-or-…",
                           icon: "key", secure: true, font: Theme.mono(12), onSubmit: save)
                    .disabled(working)
            }
            if let failure { Notice(.error, failure) }
            HStack(spacing: 8) {
                Link(destination: URL(string: "https://openrouter.ai/settings/keys")!) {
                    Label("Manage keys on OpenRouter", systemImage: "arrow.up.right")
                }
                .buttonStyle(.ghost)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel") { key = ""; dismiss() }
                    .buttonStyle(.secondary).keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "Checking…" : "Validate and Save") { save() }
                    .buttonStyle(.primary).keyboardShortcut(.defaultAction)
                    .disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.large)
        }
        .padding(20).frame(width: 480).interactiveDismissDisabled(working)
    }

    private func save() {
        let replacement = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working, !replacement.isEmpty else { return }
        working = true
        failure = nil
        Task { @MainActor in
            defer { working = false }
            do {
                try await WhistlerAuth.validateOpenRouter(key: replacement)
                guard SecretStore.write(SecretStore.openRouterKey, replacement) else {
                    throw WhistlerAuth.Failure("Could not save the key to Keychain. Your previous key has not been changed. Unlock your login Keychain and try again.")
                }
                key = ""
                onSaved()
                dismiss()
            } catch { failure = error.localizedDescription }
        }
    }
}
