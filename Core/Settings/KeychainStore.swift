import Foundation
import Security

protocol KeychainStoring {
    func readString(account: String) throws -> String?
    func writeString(_ value: String, account: String) throws
    func delete(account: String) throws
}

/// Minimal Keychain wrapper.
/// Stores the OpenAI API key.
final class KeychainStore: KeychainStoring {
    private let service: String

    init(service: String) {
        self.service = service
    }

    func readString(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func writeString(_ value: String, account: String) throws {
        let data = value.data(using: .utf8) ?? Data()

        // Upsert.
        if try readString(account: account) != nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]
            let attributes: [String: Any] = [
                kSecValueData as String: data
            ]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        } else {
            let add: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
                kSecValueData as String: data
            ]
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw KeychainError(status: status) }
        }
    }

    func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { "Keychain error (status: \(status))" }
    }
}
