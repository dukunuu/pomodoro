import Foundation
import CryptoKit

/// An optional distributed default is not confidential. Personal overrides stay in Keychain.
enum OpenRouterCredentials {
    static let bundledFilename = "build.dat"
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
        return fallbackSource
    }

    /// What will be used once the personal override is removed, preserving runtime precedence.
    static var fallbackSource: Source {
        if clean(ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]) != nil { return .environment }
        return bundledKey == nil ? .missing : .bundled
    }

    /// Removes only the personal override, never the Whistler session or mapping settings.
    static func removeStoredKey() -> Bool { SecretStore.delete(SecretStore.openRouterKey) }

    static var has: Bool { source != .missing }

    private static var bundledKey: String? {
        guard let resources = Bundle.main.resourceURL,
              let blob = try? Data(contentsOf: resources.appendingPathComponent(bundledFilename)) else { return nil }
        return unseal(blob)
    }

    private static let sealVersion: UInt8 = 1
    private static let sealNonceBytes = 16
    private static let sealPepper: [UInt8] = [
        0x9d, 0x3f, 0x6c, 0x1a, 0xe4, 0x72, 0x5b, 0x08, 0xc6, 0xa1, 0xf0, 0x4d, 0x7b, 0xe2, 0x95, 0x38,
        0x17, 0xac, 0x40, 0xe9, 0x6f, 0x2d, 0x8b, 0x5c, 0x03, 0xd1, 0x7e, 0x94, 0xa8, 0x6b, 0xf2, 0x25
    ]

    /// Reverses tools/bundle-openrouter-key.py. The seal keeps the shared key
    /// from sitting in the bundle as readable text; it is obfuscation, not
    /// encryption, since everything needed to undo it ships in this binary.
    static func unseal(_ blob: Data) -> String? {
        let bytes = [UInt8](blob)
        guard bytes.count > 1 + sealNonceBytes, bytes[0] == sealVersion else { return nil }
        let nonce = bytes[1..<(1 + sealNonceBytes)]
        let body = bytes[(1 + sealNonceBytes)...]

        var stream: [UInt8] = []
        var counter: UInt32 = 0
        while stream.count < body.count {
            var hash = SHA256()
            hash.update(data: sealPepper)
            hash.update(data: nonce)
            hash.update(data: withUnsafeBytes(of: counter.bigEndian) { Data($0) })
            stream.append(contentsOf: hash.finalize())
            counter += 1
        }
        return clean(String(bytes: zip(body, stream).map { $0 ^ $1 }, encoding: .utf8))
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !key.isEmpty && key.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) ? key : nil
    }
}
