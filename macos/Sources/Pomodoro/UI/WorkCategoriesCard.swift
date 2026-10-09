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
        Card("Work categories",
             subtitle: "Jev chooses from these names. Optional descriptions explain when to use each one. Changes apply to future sends, not existing worklogs.",
             accessory: draft != original ? AnyView(StatusPill(text: "Unsaved", tint: Theme.accent)) : nil) {
            FlowLayout(spacing: 6) {
                ForEach(draft.workCategories) { category in
                    Chip(text: category.name.isEmpty ? "Unnamed" : category.name)
                        .opacity(category.name.isEmpty ? 0.5 : 1)
                }
            }
            Disclosure("Customize categories", detail: "\(draft.workCategories.count)") {
                VStack(spacing: 8) {
                    ForEach($draft.workCategories) { $category in
                        HStack(alignment: .center, spacing: 8) {
                            VStack(spacing: 6) {
                                InputField(label: "Category name", text: $category.name,
                                           icon: "tag", font: .system(size: 13, weight: .medium))
                                InputField(label: "When to use this category",
                                           text: $category.description,
                                           prompt: "When to use this category (optional)",
                                           icon: "text.alignleft", font: .system(size: 12))
                            }
                            Button {
                                let id = category.id
                                draft.workCategories.removeAll { $0.id == id }
                            } label: {
                                Label("Remove category", systemImage: "trash").labelStyle(.iconOnly)
                            }
                            .buttonStyle(.icon)
                            .help("Remove category")
                            .disabled(draft.workCategories.count == 1)
                        }
                        .padding(9)
                        .background(Theme.controlFill.opacity(0.55),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                HStack(spacing: 8) {
                    Button { draft.workCategories.append(.init()) } label: {
                        Label("Add category", systemImage: "plus")
                    }
                    .buttonStyle(.secondary)
                    .disabled(draft.workCategories.count >= 255)
                    Button("Restore defaults") { draft.workCategories = WhistlerMappingSettings.defaultWorkCategories }
                        .buttonStyle(.ghost)
                }
            }
            Disclosure("Advanced") {
                Text("By default, out-of-office events and location markers are excluded, and unnamed focus continues previous work. Override only if needed. These switches take precedence over mapping instructions.")
                    .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 9) {
                    ToggleRow(title: "Skip out-of-office events", isOn: $draft.skipOutOfOffice)
                    RowDivider()
                    ToggleRow(title: "Skip working-location markers", isOn: $draft.skipWorkingLocation)
                    RowDivider()
                    ToggleRow(title: "Unnamed focus continues previous work", isOn: $draft.inheritUnnamedFocus)
                }
                Text("Saved exclusion rules and project mappings remain active. Use Mapping instructions for new rules, or the focus picker to choose a project. The data file is available for recovering legacy settings.")
                    .font(.caption).foregroundStyle(Theme.textMuted).fixedSize(horizontal: false, vertical: true)
                Button { openMappingData() } label: {
                    Label("Open saved mapping data…", systemImage: "doc.text")
                }
                .buttonStyle(.secondary)
            }
            if !message.isEmpty && failed { Notice(.error, message) }
            HStack(spacing: 8) {
                Button("Save") { save() }.buttonStyle(.primary)
                    .disabled(!loaded || draft == original || whistler.importRunning)
                Button("Revert") { load() }.buttonStyle(.secondary).disabled(draft == original)
                if !message.isEmpty && !failed {
                    StatusPill(text: message, tint: Theme.longBreak, systemImage: "checkmark")
                }
                Spacer()
            }
        }
        .preference(key: UnsavedChangesKey.self, value: draft != original)
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
