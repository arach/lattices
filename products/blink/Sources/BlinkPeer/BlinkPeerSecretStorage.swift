import Foundation
import Security

/// Backing store for the host's pairing secrets.
///
/// Approved-device credentials and the host agreement private key are bearer
/// secrets: anything able to read them can impersonate an approved device on
/// the LAN and pull the whole note snapshot. They must never live in a plain
/// preferences plist, which any process running as the user can read.
protocol BlinkPeerSecretStorage: AnyObject, Sendable {
    func data(forKey key: String) throws -> Data?
    func set(_ data: Data, forKey key: String) throws
    func removeValue(forKey key: String) throws
}

enum BlinkPeerSecretStorageError: Error, LocalizedError {
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .keychain(let status):
            let detail = SecCopyErrorMessageString(status, nil) as String?
            return detail ?? "Keychain error \(status)"
        }
    }
}

/// Keychain-backed storage. The Mac mirrors what the iOS companion already
/// does for its own device seed.
final class BlinkKeychainSecretStorage: BlinkPeerSecretStorage, @unchecked Sendable {
    private let service: String

    init(service: String = "dev.arach.blink.peer.host") {
        self.service = service
    }

    func data(forKey key: String) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            return item as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw BlinkPeerSecretStorageError.keychain(status)
        }
    }

    func set(_ data: Data, forKey key: String) throws {
        let query = baseQuery(key)
        let updated = SecItemUpdate(
            query as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else {
            throw BlinkPeerSecretStorageError.keychain(updated)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        #if !os(macOS)
        // Data-protection attribute; the macOS file keychain ignores it.
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        #endif
        let added = SecItemAdd(addQuery as CFDictionary, nil)
        guard added == errSecSuccess else {
            throw BlinkPeerSecretStorageError.keychain(added)
        }
    }

    func removeValue(forKey key: String) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw BlinkPeerSecretStorageError.keychain(status)
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrSynchronizable as String: false,
        ]
    }
}

/// Test double. Never used by the app.
final class BlinkInMemorySecretStorage: BlinkPeerSecretStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]

    init() {}

    func data(forKey key: String) throws -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func set(_ data: Data, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = data
    }

    func removeValue(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        values[key] = nil
    }
}
