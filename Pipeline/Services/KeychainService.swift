import Foundation
import Security

final class KeychainService {
    static let shared = KeychainService()

    private init() {}

    enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case encodingError

        var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain"
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .unexpectedStatus(let status):
                return "Keychain error: \(status)"
            case .encodingError:
                return "Failed to encode data"
            }
        }
    }

    // MARK: - API Key Management

    func saveAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecAttrService as String: "com.pipeline.app",
            kSecValueData as String: data
        ]

        // Try to delete existing item first
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getAPIKey(for provider: AIProvider) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecAttrService as String: "com.pipeline.app",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return ""
            }
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data,
              let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingError
        }

        return apiKey
    }

    func deleteAPIKey(for provider: AIProvider) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecAttrService as String: "com.pipeline.app"
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        do {
            let key = try getAPIKey(for: provider)
            return !key.isEmpty
        } catch {
            return false
        }
    }
}
