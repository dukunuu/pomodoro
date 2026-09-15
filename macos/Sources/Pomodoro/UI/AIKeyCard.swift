import SwiftUI

// Settings sections for the Whistler account and the AI that classifies
// events for it. Each piece — account, calendar, model, key — changes on its
// own, so replacing one never means re-entering the others.

/// Who the app sends worklogs as, and which calendar it reads.
struct WhistlerAccountSection: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @EnvironmentObject private var whistler: WhistlerService

    @State private var settings = WhistlerConfig.Settings()
    @State private var signedIn = false
    @State private var calendar = ""
    @State private var showingSignIn = false
    @State private var confirmingSignOut = false
    @FocusState private var calendarFocused: Bool

    private var host: String {
        URL(string: settings.apiUrl)?.host ?? settings.apiUrl
    }

    var body: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    if signedIn {
                        Button("Sign Out…") { confirmingSignOut = true }
                        Button("Switch Account…") { showingSignIn = true }
                    } else {
                        Button("Sign In…") { showingSignIn = true }
                            .buttonStyle(.borderedProminent)
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
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 260)
                    .focused($calendarFocused)
                    .onSubmit(saveCalendar)
            } label: {
                Text("Google calendar")
                Text("“primary”, or a calendar ID from Google Calendar settings.")
            }
        } header: {
            Text("Whistler account")
        } footer: {
            Text("Signing out removes only the Whistler session from Keychain. Your API key, model and mapping instructions are kept.")
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

/// The model that classifies events, and the key that pays for it.
struct AISection: View {
    @EnvironmentObject private var integrations: IntegrationStatus
    @State private var model = WhistlerConfig.defaultModel
    @State private var hasStoredKey = false
    @State private var showingModels = false
    @State private var showingKey = false

    var body: some View {
        Section {
            LabeledContent {
                Button("Change…") { showingModels = true }
            } label: {
                Label {
                    Text("Model")
                    Text(model).font(.caption.monospaced())
                } icon: {
                    Image(systemName: "cpu")
                }
            }

            LabeledContent {
                Button(hasStoredKey ? "Replace Key…" : "Add Key…") { showingKey = true }
            } label: {
                Label {
                    Text("OpenRouter API key")
                    Text(hasStoredKey ? "Stored in Keychain" : "Not set — sending is unavailable")
                } icon: {
                    Image(systemName: hasStoredKey ? "key.fill" : "key.slash")
                        .foregroundStyle(hasStoredKey ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.urgent))
                }
            }
        } header: {
            Text("AI classification")
        } footer: {
            Text("The model reads each day's event titles and your mapping instructions, then sorts the events onto Whistler projects — or skips the ones your instructions exclude. Times always come from Calendar, never from the model. Changes apply to the next send.")
        }
        .onAppear(perform: load)
        .onChange(of: integrations.whistler) { _, _ in load() }
        .sheet(isPresented: $showingModels) {
            ModelPickerSheet(current: model) { chosen in
                WhistlerConfig.update { $0.model = chosen }
                integrations.refresh()
                load()
            }
        }
        .sheet(isPresented: $showingKey) {
            AIKeySheet(replacing: hasStoredKey) {
                integrations.refresh()
                load()
            }
        }
    }

    private func load() {
        model = WhistlerConfig.readSettings().model
        hasStoredKey = SecretStore.has(SecretStore.openRouterKey)
    }
}

/// OpenRouter's catalogue, searchable, with the few models that suit this job
/// up front. A model ID can still be typed directly for anything unlisted.
struct ModelPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var current: String
    var onChoose: (String) -> Void

    @State private var models: [AIModel] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var query = ""
    @State private var selection: String?
    @State private var modelID = ""

    private var matches: [AIModel] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return models }
        return models.filter {
            $0.name.localizedCaseInsensitiveContains(text) || $0.id.localizedCaseInsensitiveContains(text)
        }
    }

    private var recommended: [AIModel] {
        OpenRouterModels.recommended.compactMap { id in models.first { $0.id == id } }
    }

    private var trimmedID: String { modelID.trimmingCharacters(in: .whitespaces) }
    private var chosenModel: AIModel? { models.first { $0.id == trimmedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose AI Model").font(.headline)
                Text("Used to classify every send. Cheaper, faster models are usually enough; try a larger one if events are misfiled or your skip rules are ignored.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextField("Search models", text: $query, prompt: Text("Search by name or ID"))
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
            }
            .padding(20)

            List(selection: $selection) {
                if query.isEmpty && !recommended.isEmpty {
                    Section("Recommended") {
                        ForEach(recommended) { row($0) }
                    }
                }
                Section(query.isEmpty ? "All models" : "\(matches.count) matching") {
                    ForEach(matches) { row($0) }
                }
            }
            .listStyle(.inset)
            .overlay {
                if loading {
                    ProgressView("Loading OpenRouter models…")
                } else if let failure {
                    VStack(spacing: 6) {
                        Image(systemName: "wifi.exclamationmark").font(.title2).foregroundStyle(.secondary)
                        Text(failure).font(.callout)
                        Text("You can still type a model ID below.").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding()
                } else if matches.isEmpty {
                    Text("No models match “\(query)”.").foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Text("Model ID")
                    TextField("Model ID", text: $modelID, prompt: Text("provider/model"))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.body.monospaced())
                }
                Group {
                    if let chosenModel {
                        Text("\(chosenModel.name) · \(chosenModel.priceLabel)"
                             + (chosenModel.supportsJSON ? "" : " · no JSON mode, may need a retry"))
                    } else if !models.isEmpty && !trimmedID.isEmpty {
                        Text("Not in OpenRouter's catalogue — sends will fail if this ID is wrong.")
                            .foregroundStyle(Theme.urgent)
                    } else {
                        Text(" ")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

                HStack {
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Use Model") {
                        onChoose(trimmedID)
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(trimmedID.isEmpty || trimmedID == current)
                }
                .controlSize(.large)
                .padding(.top, 6)
            }
            .padding(20)
        }
        .frame(width: 580, height: 620)
        .onAppear {
            modelID = current
            selection = current
        }
        .onChange(of: selection) { _, value in
            if let value { modelID = value }
        }
        .task { await load() }
    }

    private func row(_ model: AIModel) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.name)
                    if model.id == current {
                        Text("Current")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor.opacity(0.18), in: Capsule())
                    }
                }
                Text(model.id)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(model.priceLabel).font(.caption).monospacedDigit()
                Text(model.contextLabel).font(.caption2).foregroundStyle(.tertiary)
            }
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .tag(model.id)
        .help(model.supportsJSON ? model.id : "\(model.id) — does not advertise JSON mode")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            models = try await OpenRouterModels.fetch()
            failure = nil
        } catch {
            failure = error.localizedDescription
        }
    }
}

/// Replacing the OpenRouter key on its own, without touching the Whistler
/// sign-in beside it.
struct AIKeySheet: View {
    @Environment(\.dismiss) private var dismiss
    var replacing: Bool
    var onSaved: () -> Void
    @State private var key = ""
    @State private var working = false
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(replacing ? "Replace API Key" : "Add API Key")
                .font(.headline)
            Text("Enter an OpenRouter key. It is checked with OpenRouter before it \(replacing ? "replaces your current key" : "is stored") in the login Keychain. Your Whistler sign-in and model are not changed.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("OpenRouter API key", text: $key, prompt: Text("sk-or-…"))
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .disabled(working)
            Link("Manage keys on OpenRouter", destination: URL(string: "https://openrouter.ai/settings/keys")!)
                .font(.callout)

            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Theme.urgent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { key = ""; dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(working)
                Button(working ? "Checking…" : "Validate and Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(working || key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled(working)
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
            } catch {
                failure = error.localizedDescription
            }
        }
    }
}
