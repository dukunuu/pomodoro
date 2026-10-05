import Foundation

/// An optional distributed default is not confidential. Personal overrides stay in Keychain.
enum OpenRouterCredentials {
    static let bundledFilename = "openrouter-default-key.txt"
    enum Source { case stored, environment, bundled, missing }

    static func select(stored: String?, environment: String?, bundled: String?) -> String? {
        clean(stored) ?? clean(environment) ?? clean(bundled)
    }

    static var read: String? {
        select(stored: SecretStore.read(SecretStore.openRouterKey),
               environment: ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], bundled: bundledKey)
    }

    static var source: Source {
        if clean(SecretStore.read(SecretStore.openRouterKey)) != nil { return .stored }
        if clean(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]) != nil { return .environment }
        return bundledKey == nil ? .missing : .bundled
    }

    static var has: Bool { source != .missing }

    private static var bundledKey: String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        return clean(try? String(contentsOf: resources.appendingPathComponent(bundledFilename), encoding: .utf8))
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) ? key : nil
    }
}
