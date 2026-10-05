import Foundation

/// Non-secret mapping preferences. Alias targets are IDs, partitioned by account.
struct WhistlerMappingSettings: Codable, Equatable {
    struct SkipRule: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var title = ""
        var match = "contains"
        var enabled = true
    }

    struct ProjectAlias: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var projectId = ""
        var alias = ""
    }

    struct WorkCategory: Codable, Equatable, Identifiable {
        var id = UUID().uuidString
        var name = ""
        var description = ""

        enum CodingKeys: String, CodingKey { case id, name, description }
        init(id: String = UUID().uuidString, name: String = "", description: String = "") {
            self.id = id; self.name = name; self.description = description
        }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            name = try values.decode(String.self, forKey: .name)
            description = values.contains(.description) ? try values.decode(String.self, forKey: .description) : ""
        }
    }

    static let defaultWorkCategories: [WorkCategory] = [
        .init(id: "implementation", name: "Implementation"), .init(id: "bugfix", name: "Bug fix"),
        .init(id: "meetings", name: "Meetings"), .init(id: "reviews", name: "PR reviews"),
        .init(id: "management", name: "Management"), .init(id: "work", name: "Work")
    ]

    var version = 1
    var skipOutOfOffice = true
    var skipWorkingLocation = true
    var inheritUnnamedFocus = true
    var customSkipRules: [SkipRule] = []
    var workCategories = Self.defaultWorkCategories
    var projectAliases: [String: [ProjectAlias]] = [:]

    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let text) = self { return text }
            return nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case version, skipOutOfOffice, skipWorkingLocation, inheritUnnamedFocus, customSkipRules, projectAliases, workCategories
    }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = values.contains(.version) ? try values.decode(Int.self, forKey: .version) : 1
        skipOutOfOffice = values.contains(.skipOutOfOffice) ? try values.decode(Bool.self, forKey: .skipOutOfOffice) : true
        skipWorkingLocation = values.contains(.skipWorkingLocation) ? try values.decode(Bool.self, forKey: .skipWorkingLocation) : true
        inheritUnnamedFocus = values.contains(.inheritUnnamedFocus) ? try values.decode(Bool.self, forKey: .inheritUnnamedFocus) : true
        customSkipRules = values.contains(.customSkipRules) ? try values.decode([SkipRule].self, forKey: .customSkipRules) : []
        projectAliases = values.contains(.projectAliases) ? try values.decode([String: [ProjectAlias]].self, forKey: .projectAliases) : [:]
        workCategories = values.contains(.workCategories) ? try values.decode([WorkCategory].self, forKey: .workCategories) : Self.defaultWorkCategories
    }

    static func scope(_ settings: WhistlerConfig.Settings) -> String {
        var url = settings.apiUrl
        while url.hasSuffix("/") { url.removeLast() }
        return url + "|" + settings.email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func normalized(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    func validate() throws {
        guard version == 1 else { throw Failure.invalid("Unsupported mapping settings version.") }
        guard (1...255).contains(workCategories.count) else {
            throw Failure.invalid("Choose between 1 and 255 work categories.")
        }
        var ids: Set<String> = []
        var names: Set<String> = []
        for category in workCategories {
            guard category.id.range(of: #"\A[A-Za-z0-9_-]{1,64}\z"#, options: .regularExpression) != nil,
                  ids.insert(category.id).inserted, !Self.normalized(category.name).isEmpty,
                  names.insert(Self.normalized(category.name)).inserted else {
                throw Failure.invalid("Each work category needs a unique ID and name, and an optional description.")
            }
        }
        ids = []
        for rule in customSkipRules {
            guard !rule.id.isEmpty, ids.insert(rule.id).inserted,
                  !Self.normalized(rule.title).isEmpty,
                  ["contains", "equals", "prefix"].contains(rule.match) else {
                throw Failure.invalid("Each custom rule needs a literal title and a match mode.")
            }
        }
        for aliases in projectAliases.values {
            var targets: [String: String] = [:]
            ids = []
            for item in aliases {
                let label = Self.normalized(item.alias)
                guard !label.isEmpty, !item.projectId.isEmpty, !item.id.isEmpty,
                      ids.insert(item.id).inserted else {
                    throw Failure.invalid("Each alias needs a Calendar label and a Whistler project.")
                }
                if let target = targets[label], target != item.projectId {
                    throw Failure.invalid("The same alias points to different projects. Review its targets.")
                }
                targets[label] = item.projectId
            }
        }
    }

    static func read() throws -> Self {
        let data: Data
        do { data = try Data(contentsOf: DataPaths.whistlerMapping) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return Self()
        }
        let settings = try JSONDecoder().decode(Self.self, from: data)
        try settings.validate()
        return settings
    }

    /// The visible editor owns categories/defaults, not saved rules or picker aliases.
    func updatingWorkPreferences(from edited: Self) throws -> Self {
        var result = self
        result.skipOutOfOffice = edited.skipOutOfOffice
        result.skipWorkingLocation = edited.skipWorkingLocation
        result.inheritUnnamedFocus = edited.inheritUnnamedFocus
        result.workCategories = edited.workCategories
        try result.validate()
        return result
    }

    func save() throws {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard let text = String(data: data, encoding: .utf8),
              AtomicFile.write(text + "\n", to: DataPaths.whistlerMapping) else {
            throw Failure.invalid("Could not save mapping settings.")
        }
    }
}

struct WhistlerMappingProject: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
}
