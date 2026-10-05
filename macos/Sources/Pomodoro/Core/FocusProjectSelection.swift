import Foundation

/// A picker choice becomes a visible Calendar tag and an account-scoped ID lock.
/// Preserve old labels after project renames so historical events still map correctly.
enum FocusProjectSelection {
    static func select(projectId: String, name: String, scope: String,
                       settings: inout WhistlerMappingSettings) throws -> String {
        try settings.validate()
        guard !projectId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              projectId.utf16.count <= 64, !WhistlerMappingSettings.normalized(name).isEmpty else {
            throw WhistlerMappingSettings.Failure.invalid("Select an active Whistler project.")
        }
        let clean = name.replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        var label = ""
        for character in clean {
            let next = String(character)
            if label.utf16.count + next.utf16.count > 150 { break }
            label += next
        }
        // Never create an alias that locks plain unnamed Focus time to this project.
        let normalizedLabel = WhistlerMappingSettings.normalized(label)
        if normalizedLabel == "focus" || normalizedLabel == "focus time" { label = "Project: " + label }
        var aliases = settings.projectAliases[scope] ?? []
        if aliases.contains(where: { WhistlerMappingSettings.normalized($0.alias) == WhistlerMappingSettings.normalized(label) && $0.projectId != projectId }) {
            label += " · " + projectId
        }
        if aliases.contains(where: { WhistlerMappingSettings.normalized($0.alias) == WhistlerMappingSettings.normalized(label) && $0.projectId != projectId }) {
            throw WhistlerMappingSettings.Failure.invalid("Focus label conflicts with a project alias. Review Project aliases.")
        }
        if !aliases.contains(where: { WhistlerMappingSettings.normalized($0.alias) == WhistlerMappingSettings.normalized(label) && $0.projectId == projectId }) {
            aliases.append(.init(projectId: projectId, alias: label))
        }
        settings.projectAliases[scope] = aliases
        try settings.validate()
        return "[\(label)] Focus time"
    }
}
