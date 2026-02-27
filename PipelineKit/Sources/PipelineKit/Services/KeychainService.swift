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
        try setAPIKeys([apiKey], for: provider)
    }

    public func addAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        var keys = try getAPIKeys(for: provider)
        if !keys.contains(candidate) {
            keys.append(candidate)
            try setAPIKeys(keys, for: provider)
        }
    }

    public func getAPIKeys(for provider: AIProvider) throws -> [String] {
        if let data = try readData(for: provider, account: apiKeysAccount(for: provider)) {
            let decoded = try decodeAPIKeys(from: data)
            let normalized = normalizeAPIKeys(decoded)
            if normalized != decoded {
                try setAPIKeys(normalized, for: provider)
            }
            return normalized
        }

        let legacy = try getLegacyAPIKey(for: provider)
        return normalizeAPIKeys([legacy])
    }

    public func setAPIKeys(_ apiKeys: [String], for provider: AIProvider) throws {
        let normalized = normalizeAPIKeys(apiKeys)
        guard !normalized.isEmpty else {
            try deleteAPIKey(for: provider)
            return
        }

        let data: Data
        do {
            data = try JSONEncoder().encode(normalized)
        } catch {
            throw KeychainError.encodingError
        }

        try writeData(data, for: provider, account: apiKeysAccount(for: provider))
        try writeLegacyAPIKey(normalized[0], for: provider)
    }

    public func removeAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        let candidate = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }

        var keys = try getAPIKeys(for: provider)
        keys.removeAll { $0 == candidate }
        try setAPIKeys(keys, for: provider)
    }

    public func removeAPIKey(at index: Int, for provider: AIProvider) throws {
        var keys = try getAPIKeys(for: provider)
        guard keys.indices.contains(index) else { return }
        keys.remove(at: index)
        try setAPIKeys(keys, for: provider)
    }

    public func getAPIKey(for provider: AIProvider) throws -> String {
        try getAPIKeys(for: provider).first ?? ""
    }

    public func deleteAPIKey(for provider: AIProvider) throws {
        try deleteData(for: provider, account: provider.keychainKey)
        try deleteData(for: provider, account: apiKeysAccount(for: provider))
    }

    // MARK: - Private

    private func apiKeysAccount(for provider: AIProvider) -> String {
        "\(provider.keychainKey).keys"
    }

    private func baseQuery(for provider: AIProvider, account: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: Constants.App.bundleID,
        ]
        #if !targetEnvironment(simulator)
        query[kSecAttrAccessGroup as String] = KeychainService.accessGroup
        #endif
        return query
    }

    private func normalizeAPIKeys(_ apiKeys: [String]) -> [String] {
        apiKeys
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
    }

    private func decodeAPIKeys(from data: Data) throws -> [String] {
        if let keys = try? JSONDecoder().decode([String].self, from: data) {
            return keys
        }

        if let key = String(data: data, encoding: .utf8) {
            return [key]
        }

        throw KeychainError.encodingError
    }

    private func getLegacyAPIKey(for provider: AIProvider) throws -> String {
        guard let data = try readData(for: provider, account: provider.keychainKey) else {
            return ""
        }

        guard let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainError.encodingError
        }

        return apiKey
    }

    private func writeLegacyAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        guard let data = apiKey.data(using: .utf8) else {
            throw KeychainError.encodingError
        }
        try writeData(data, for: provider, account: provider.keychainKey)
    }

    private func readData(for provider: AIProvider, account: String) throws -> Data? {
        var query = baseQuery(for: provider, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }

        guard let data = result as? Data else {
            throw KeychainError.encodingError
        }

        return data
    }

    private func writeData(_ data: Data, for provider: AIProvider, account: String) throws {
        let query = baseQuery(for: provider, account: account)
        _ = SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private func deleteData(for provider: AIProvider, account: String) throws {
        let status = SecItemDelete(baseQuery(for: provider, account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func hasAPIKey(for provider: AIProvider) -> Bool {
        do {
            return !(try getAPIKeys(for: provider)).isEmpty
        } catch {
            return false
        }
    }
}
