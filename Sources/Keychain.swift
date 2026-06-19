import Foundation
import Security

/// Minimal wrapper around the macOS Keychain for storing secrets (API keys).
/// Secrets live as generic-password items under the app's bundle identifier, so
/// they're encrypted at rest and never written to `UserDefaults` or the repo.
enum Keychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.narrateify.Narrateify"

    /// Stores (or clears, when `value` is empty) the secret for `account`.
    static func set(_ value: String, account: String) {
        guard !value.isEmpty else { delete(account: account); return }
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // Available after first unlock; not synced to iCloud.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { _, new in new }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// Reads the secret for `account`, or `nil` if none is stored.
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Returns the Keychain value for `account`, transparently migrating a
    /// legacy plaintext `UserDefaults` value into the Keychain (and deleting the
    /// plaintext copy) the first time it runs. Existing users keep their key
    /// without re-entering it; the cleartext copy is removed.
    static func migratingValue(account: String, legacyDefaultsKey: String) -> String {
        if let secret = get(account: account) { return secret }
        let defaults = UserDefaults.standard
        if let legacy = defaults.string(forKey: legacyDefaultsKey), !legacy.isEmpty {
            set(legacy, account: account)
            defaults.removeObject(forKey: legacyDefaultsKey)
            return legacy
        }
        return ""
    }
}
