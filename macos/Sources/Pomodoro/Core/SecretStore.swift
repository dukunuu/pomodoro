import Foundation
import Security

/// Secrets in the login Keychain rather than in a file.
///
/// The session token and the OpenRouter key used to live in
/// pomodoro-whistler.env as plain text, beside the account password typed
/// there to obtain the token. The Keychain encrypts them at rest, and the user
/// can inspect or revoke them in Keychain Access without going through this
/// app. Windows does the same thing through Credential Manager.
enum SecretStore {
    static let whistlerSession = "whistler-session"
    static let openRouterKey = "openrouter-key"

    private static let service = "com.dukunuu.pomodoro"

    static func has(_ key: String) -> Bool { !(read(key) ?? "").isEmpty }

    static func read(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Storing an empty value removes the item.
    @discardableResult
    static func write(_ key: String, _ value: String) -> Bool {
        guard !value.isEmpty else { delete(key); return true }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let data = Data(value.utf8)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ] as CFDictionary)
    }
}
