import AppKit
import SwiftUI

/// Categories are optional; default behavior overrides stay out of the normal flow.
struct WorkCategoriesCard: View {
    @EnvironmentObject private var whistler: WhistlerService
    @State private var draft = WhistlerMappingSettings()
    @State private var original = WhistlerMappingSettings()
    @State private var scope = ""
    @State private var loaded = false
    @State private var message = ""
    @State private var failed = false

    private var currentScope: String { WhistlerMappingSettings.scope(WhistlerConfig.readSettings()) }

    var body: some View {
        Card("Work categories") {
            Text("Jev chooses from these names. Optional descriptions explain when to use each one. Changes apply to future sends, not existing worklogs.")
                .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
            Text(draft.workCategories.map(\.name).joined(separator: " · "))
                .font(.caption).foregroundStyle(Theme.textMuted)
            DisclosureGroup("Customize categories") {
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
            DisclosureGroup("Advanced") {
                Text("By default, out-of-office events and location markers are excluded, and unnamed focus continues previous work. Override only if needed. These switches take precedence over mapping instructions.")
                    .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                Toggle("Skip out-of-office events", isOn: $draft.skipOutOfOffice)
                Toggle("Skip working-location markers", isOn: $draft.skipWorkingLocation)
                Toggle("Unnamed focus continues previous work", isOn: $draft.inheritUnnamedFocus)
                Text("Saved exclusion rules and project mappings remain active. Use Mapping instructions for new rules, or the focus picker to choose a project. The data file is available for recovering legacy settings.")
                    .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                Button("Open saved mapping data…") { openMappingData() }
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
            // Merge only visible preferences; preserve even newly saved focus-picker aliases.
            let latest = try WhistlerMappingSettings.read().updatingWorkPreferences(from: draft)
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

    private func openMappingData() {
        do {
            if !FileManager.default.fileExists(atPath: DataPaths.whistlerMapping.path) {
                try WhistlerMappingSettings.read().save()
            }
            guard NSWorkspace.shared.open(DataPaths.whistlerMapping) else {
                throw WhistlerMappingSettings.Failure.invalid("Could not open the mapping data file.")
            }
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
