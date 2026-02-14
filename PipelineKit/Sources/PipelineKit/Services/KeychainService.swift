import Foundation
import Security

public final class KeychainService {
    public static let shared = KeychainService()

    /// Keychain access group for sharing between app and extensions.
    /// Uses the team ID prefix + bundle ID pattern.
    public static let accessGroup = "io.github.digitaltracer.pipeline"

    private init() {}

    public enum KeychainError: LocalizedError {
        case itemNotFound
        case duplicateItem
        case unexpectedStatus(OSStatus)
        case encodingError

        public var errorDescription: String? {
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

    public func saveAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingError
        }

        var query = baseQuery(for: provider)
        query[kSecValueData as String] = data

        // Try to delete existing item first
        SecItemDelete(baseQuery(for: provider) as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func getAPIKey(for provider: AIProvider) throws -> String {
        var query = baseQuery(for: provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

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

    public func deleteAPIKey(for provider: AIProvider) throws {
        let query = baseQuery(for: provider)

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: - Private

    private func baseQuery(for provider: AIProvider) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: provider.keychainKey,
            kSecAttrService as String: Constants.App.bundleID,
        ]
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = KeychainService.accessGroup
        #endif
        return query
    }

    public func hasAPIKey(for provider: AIProvider) -> Bool {
        do {
            let key = try getAPIKey(for: provider)
            return !key.isEmpty
        } catch {
            return false
        }
    }
}
