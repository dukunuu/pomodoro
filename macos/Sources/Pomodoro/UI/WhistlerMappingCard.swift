import SwiftUI

/// Optional refinements; plain-language mapping instructions are the primary editor.
struct WhistlerMappingCard: View {
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = WhistlerMappingSettings()
    @State private var original = WhistlerMappingSettings()
    @State private var scope = ""
    @State private var loaded = false
    @State private var message = ""
    @State private var failed = false

    private var currentScope: String { WhistlerMappingSettings.scope(WhistlerConfig.readSettings()) }
    private var aliases: Binding<[WhistlerMappingSettings.ProjectAlias]> {
        Binding(get: { draft.projectAliases[scope] ?? [] }, set: { draft.projectAliases[scope] = $0 })
    }

    var body: some View {
        Card("Mapping preferences") {
            Text("Changes apply to the next send. Known Calendar event types are controlled by these switches, even if old instructions exclude them.")
                .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Toggle("Skip out-of-office events", isOn: $draft.skipOutOfOffice)
            Toggle("Skip working-location markers (Office / Home)", isOn: $draft.skipWorkingLocation)
            Toggle("Unnamed Focus time continues previous work", isOn: $draft.inheritUnnamedFocus)
            Text("All-day events have no timed hours. Unnamed focus continues previous work by default; no instruction is needed.")
                .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)

            Divider().padding(.vertical, 4)
            DisclosureGroup("Work categories · customize") {
                Text("Jev chooses from these names. Optional descriptions explain when to use each one. Changes affect future sends, not existing worklogs.")
                    .font(.caption).foregroundStyle(Theme.textMuted)
                ForEach($draft.workCategories) { $category in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            TextField("Category name", text: $category.name)
                            TextField("When to use this category (optional)", text: $category.description)
                                .font(.caption)
                        }
                        Button {
                            let id = category.id
                            draft.workCategories.removeAll { $0.id == id }
                        } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.plain).help("Remove category")
                        .disabled(draft.workCategories.count == 1)
                    }.padding(.vertical, 3)
                }
                HStack {
                    Button("Add category") { draft.workCategories.append(.init()) }
                        .disabled(draft.workCategories.count >= 255)
                    Button("Restore defaults") { draft.workCategories = WhistlerMappingSettings.defaultWorkCategories }
                }
            }
            Text(draft.workCategories.map(\.name).joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.textMuted)

            Divider().padding(.vertical, 4)
            DisclosureGroup("Advanced · literal exclusions & project aliases") {
            Text("Usually, describe exclusions and aliases in Mapping instructions instead. Enabled literal rules win; unchecked matching rules block exclusions from instructions.")
                .font(.caption).foregroundStyle(Theme.textMuted)
            Text("Literal exclusions").font(.headline)
            ForEach($draft.customSkipRules) { $rule in
                HStack {
                    Toggle("Enabled", isOn: $rule.enabled).labelsHidden()
                    TextField("Event title or phrase", text: $rule.title)
                    Picker("Match", selection: $rule.match) {
                        Text("Contains").tag("contains")
                        Text("Exact title").tag("equals")
                        Text("Starts with").tag("prefix")
                    }.labelsHidden().frame(width: 115)
                    Button {
                        let id = rule.id
                        draft.customSkipRules.removeAll { $0.id == id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).help("Remove exclusion")
                }
            }
            Button("Add exclusion") { draft.customSkipRules.append(.init()) }

            Divider().padding(.vertical, 4)
            HStack {
                Text("Project aliases").font(.headline)
                Spacer()
                if whistler.mappingProjectsLoading { ProgressView().controlSize(.small) }
                Button("Load projects") { whistler.refreshMappingProjects() }
                    .disabled(!WhistlerConfig.isSignedIn || whistler.mappingProjectsLoading)
            }
            Text("Choose a Whistler project, then its Calendar label—for example ‘Opeone to Quotomy’. Matches exact labels, [tags], and title prefixes. Aliases belong only to the signed-in account.")
                .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            ForEach(aliases) { $alias in
                HStack {
                    Picker("Project", selection: $alias.projectId) {
                        Text("Select project").tag("")
                        if !alias.projectId.isEmpty && !whistler.mappingProjects.contains(where: { $0.id == alias.projectId }) {
                            Text("Saved project — reload to verify").tag(alias.projectId)
                        }
                        ForEach(whistler.mappingProjects) { project in
                            Text(project.name).tag(project.id)
                        }
                    }.labelsHidden().frame(minWidth: 130, maxWidth: 200)
                    TextField("Calendar label", text: $alias.alias)
                    Button {
                        let id = alias.id
                        draft.projectAliases[scope, default: []].removeAll { $0.id == id }
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.plain).help("Remove alias")
                }
            }
            Button("Add alias") { draft.projectAliases[scope, default: []].append(.init()) }
                .disabled(whistler.mappingProjects.isEmpty)
            if !whistler.mappingProjectsMessage.isEmpty {
                Text(whistler.mappingProjectsMessage).font(.caption).foregroundStyle(Theme.textMuted)
            }
            }
            HStack {
                Button("Save") { save() }.buttonStyle(.borderedProminent)
                    .disabled(!loaded || draft == original || whistler.importRunning)
                Button("Revert") { load() }.disabled(draft == original)
                if !message.isEmpty {
                    Text(message).font(.caption).foregroundStyle(failed ? Theme.urgent : Theme.longBreak)
                }
                Spacer()
            }.padding(.top, 5)
        }
        .onAppear { load() }
        .onChange(of: currentScope) { _, _ in load() }
    }

    private func load() {
        scope = currentScope
        do {
            draft = try WhistlerMappingSettings.read()
            original = draft
            loaded = true
            message = ""
            failed = false
        } catch {
            loaded = false
            failed = true
            message = error.localizedDescription
        }
    }

    private func save() {
        guard !whistler.importRunning else { return }
        guard scope == currentScope else { load(); return }
        do {
            try draft.validate()
            // Preserve any aliases saved for other accounts since the draft opened.
            var latest = try WhistlerMappingSettings.read()
            latest.skipOutOfOffice = draft.skipOutOfOffice
            latest.skipWorkingLocation = draft.skipWorkingLocation
            latest.inheritUnnamedFocus = draft.inheritUnnamedFocus
            latest.customSkipRules = draft.customSkipRules
            latest.workCategories = draft.workCategories
            latest.projectAliases[scope] = draft.projectAliases[scope] ?? []
            try latest.save()
            draft = latest
            original = latest
            failed = false
            message = "Saved"
            whistler.mappingDidChange()
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
