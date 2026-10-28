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

    /// In-memory session cache so repeated dictations and status checks avoid synchronous
    /// `securityd` IPC overhead (~40–120ms per call). Updated/cleared on store or delete.
    private static let cacheLock = NSLock()
    private static var cachedSecrets: [String: String] = [:]
    private static var cachedStatuses: [String: Status] = [:]

    static func read(account: String) -> String? {
        cacheLock.lock()
        if let cached = cachedSecrets[account] {
            cacheLock.unlock()
            return cached
        }
        if cachedStatuses[account] == .absent {
            cacheLock.unlock()
            return nil
        }
        cacheLock.unlock()

        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let copyStatus = SecItemCopyMatching(query as CFDictionary, &item)
        guard copyStatus == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            if copyStatus == errSecItemNotFound {
                cacheLock.lock()
                cachedStatuses[account] = .absent
                cachedSecrets.removeValue(forKey: account)
                cacheLock.unlock()
            }
            return nil
        }
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        cacheLock.lock()
        cachedSecrets[account] = trimmed
        cachedStatuses[account] = .present
        cacheLock.unlock()
        return trimmed
    }

    enum Status {
        case present
        case absent
        /// Locked, denied or otherwise unreadable: not the same as no key (D-84).
        case unavailable
    }

    /// Whether a key exists, asked by attributes only: fetching the secret itself on the
    /// main thread could block the window on an access prompt (D-170).
    static func status(account: String) -> Status {
        cacheLock.lock()
        if let cached = cachedStatuses[account], cached != .unavailable {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        var query = baseQuery(account: account)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let resolved: Status
        switch SecItemCopyMatching(query as CFDictionary, &item) {
        case errSecSuccess: resolved = .present
        case errSecItemNotFound: resolved = .absent
        default: resolved = .unavailable
        }
        if resolved != .unavailable {
            cacheLock.lock()
            cachedStatuses[account] = resolved
            cacheLock.unlock()
        }
        return resolved
    }

    static func hasKey(account: String) -> Bool {
        status(account: account) == .present
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
            cacheLock.lock()
            cachedSecrets[account] = trimmed
            cachedStatuses[account] = .present
            cacheLock.unlock()
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
        let added = SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        if added {
            cacheLock.lock()
            cachedSecrets[account] = trimmed
            cachedStatuses[account] = .present
            cacheLock.unlock()
        }
        return added
    }

    static func delete(account: String) -> KeychainDeleteResult {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        switch status {
        case errSecSuccess:
            cacheLock.lock()
            cachedSecrets.removeValue(forKey: account)
            cachedStatuses[account] = .absent
            cacheLock.unlock()
            return .removed
        case errSecItemNotFound:
            cacheLock.lock()
            cachedSecrets.removeValue(forKey: account)
            cachedStatuses[account] = .absent
            cacheLock.unlock()
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
