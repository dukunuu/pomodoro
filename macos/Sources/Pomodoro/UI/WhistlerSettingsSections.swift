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
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if signedIn {
                        Button("Sign Out…") { confirmingSignOut = true }
                        Button("Switch Account…") { showingSignIn = true }
                    } else {
                        Button("Sign In…") { showingSignIn = true }.buttonStyle(.borderedProminent)
                    }
                }
            } label: {
                Label {
                    Text(signedIn ? (settings.email.isEmpty ? "Signed in" : settings.email) : "Not signed in")
                    Text(signedIn ? host : "Sign in to send worklogs to Whistler.")
                } icon: {
                    Image(systemName: signedIn ? "person.crop.circle.fill" : "person.crop.circle.badge.questionmark")
                        .font(.title2)
                        .foregroundStyle(signedIn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                }
            }
            LabeledContent {
                TextField("Google calendar", text: $calendar, prompt: Text(WhistlerConfig.defaultCalendar))
                    .labelsHidden().multilineTextAlignment(.trailing).frame(maxWidth: 260)
                    .focused($calendarFocused).onSubmit(saveCalendar)
            } label: {
                Text("Google calendar")
                Text("“primary”, or a calendar ID from Google Calendar settings.")
            }
        } header: {
            Text("Whistler account")
        } footer: {
            Text("Signing out removes only the Whistler session from Keychain. Your API key and mapping instructions are kept.")
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
    @State private var showingKey = false
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

    var body: some View {
        Section {
            LabeledContent("Mapping engine", value: "Jev")
            if hasKey {
                DisclosureGroup("Advanced") { apiKeyConfiguration }
            } else {
                apiKeyConfiguration
            }
        } header: {
            Text("Project mapping")
        } footer: {
            Text("Jev maps Calendar events to your Whistler projects using your aliases and skip rules. Configure those in Whistler. Hours and worklog text are assembled locally; there is no model to choose.")
        }
        .onAppear(perform: load)
        .onChange(of: integrations.whistler) { _, _ in load() }
        .sheet(isPresented: $showingKey) {
            AIKeySheet(replacing: hasStoredKey) { integrations.refresh(); load() }
        }
    }

    private var apiKeyConfiguration: some View {
        LabeledContent {
            Button(hasStoredKey ? "Replace Key…" : hasKey ? "Use Own Key…" : "Add Key…") { showingKey = true }
        } label: {
            Label {
                Text(hasKey ? "Personal API key override" : "OpenRouter API key")
                Text(keyDescription)
            } icon: {
                Image(systemName: hasKey ? "key.fill" : "key.slash")
                    .foregroundStyle(hasKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.urgent))
            }
        }
    }

    private func load() { keySource = OpenRouterCredentials.source }
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
        VStack(alignment: .leading, spacing: 14) {
            Text(replacing ? "Replace API Key" : "Add API Key").font(.headline)
            Text("Enter an OpenRouter key. It is checked with OpenRouter before it \(replacing ? "replaces your current key" : "is stored") in the login Keychain. Your Whistler sign-in and mapping rules are not changed.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("OpenRouter API key", text: $key, prompt: Text("sk-or-…"))
                .textFieldStyle(.roundedBorder).controlSize(.large).disabled(working)
            Link("Manage keys on OpenRouter", destination: URL(string: "https://openrouter.ai/settings/keys")!).font(.callout)
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(Theme.urgent).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { key = ""; dismiss() }.keyboardShortcut(.cancelAction).disabled(working)
                Button(working ? "Checking…" : "Validate and Save") { save() }
                    .keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
                    .disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.controlSize(.large)
        }
        .padding(20).frame(width: 460).interactiveDismissDisabled(working)
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
