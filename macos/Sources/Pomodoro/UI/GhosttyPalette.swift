import Foundation

/// Resolves Ghostty's selected dark palette (both apps use a dark appearance).
/// User themes precede bundled themes; explicit config colors override the theme.
enum GhosttyPalette {
    static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                     bundledThemes: URL = URL(fileURLWithPath: "/Applications/Ghostty.app/Contents/Resources/ghostty/themes")) -> [String: String] {
        let fm = FileManager.default
        let configHome = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
            .map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".config")
        let directories = [configHome.appendingPathComponent("ghostty"),
                           home.appendingPathComponent("Library/Application Support/com.mitchellh.ghostty")]
        var config: [String: String] = [:]
        for directory in directories {
            // Ghostty prefers config.ghostty over the legacy config filename.
            let modern = directory.appendingPathComponent("config.ghostty")
            let file = fm.fileExists(atPath: modern.path) ? modern : directory.appendingPathComponent("config")
            config.merge(parse(file)) { _, new in new }
        }
        var name = config["theme"] ?? ""
        if name.contains("dark:") {
            name = name.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                .first(where: { $0.hasPrefix("dark:") }).map { String($0.dropFirst(5)) } ?? name
        }
        name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var values: [String: String] = [:]
        if !name.isEmpty {
            let candidates: [URL]
            if name.hasPrefix("/") || name.hasPrefix("~/") {
                candidates = [URL(fileURLWithPath: (name as NSString).expandingTildeInPath)]
            } else {
                candidates = directories.map { $0.appendingPathComponent("themes").appendingPathComponent(name) }
                    + [bundledThemes.appendingPathComponent(name),
                       home.appendingPathComponent("Applications/Ghostty.app/Contents/Resources/ghostty/themes").appendingPathComponent(name)]
            }
            if let file = candidates.first(where: { fm.fileExists(atPath: $0.path) }) {
                values = parse(file)
            }
        }
        values.merge(config) { _, new in new }
        return values.filter { key, value in
            let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
            return (key.hasPrefix("palette.") || ["background", "foreground", "selection-background", "selection-foreground", "cursor-color"].contains(key))
                && hex.count == 6 && UInt32(hex, radix: 16) != nil
        }
    }

    private static func parse(_ file: URL) -> [String: String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#") else { continue }
            let pair = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard pair.count == 2 else { continue }
            if pair[0] == "palette" {
                let color = pair[1].split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                if color.count == 2 { result["palette.\(color[0])"] = color[1] }
            } else { result[pair[0]] = pair[1] }
        }
        return result
    }
}
