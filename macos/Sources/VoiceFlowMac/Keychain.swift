import Foundation
import Security

enum KeychainDeleteResult: Equatable {
    case removed
    case notFound
    case failed(OSStatus)
}

/// The app's half of the credential contract.
///
/// The key is stored once here and read back only to hand it to the engine process.
/// Nothing writes it to a preference, a log, or a project file, and no accessor returns
/// it to the interface, which shows only whether a key exists.
enum Keychain {
    /// Shared with the Python engine's `credentials.py`, so the terminal and the app
    /// address the same item rather than each keeping their own copy.
    static let service = "sanblue.voiceflow"

    static func read(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            return nil
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func hasKey(account: String) -> Bool {
        read(account: account) != nil
    }

    @discardableResult
    static func store(_ secret: String, account: String) -> Bool {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8), !trimmed.isEmpty else {
            return false
        }

        let query = baseQuery(account: account)
        let update = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updated == errSecSuccess {
            return true
        }
        guard updated == errSecItemNotFound else {
            return false
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrLabel as String] = "sanblueᵈᵒᵗ VoiceFlow — \(account)"
        // The key is needed only while the speaker is using this Mac, and it must never
        // travel to another device inside a keychain sync.
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) -> KeychainDeleteResult {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess:
            return .removed
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed(status)
        }
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
