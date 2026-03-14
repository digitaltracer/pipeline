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
        case authenticationFailed
        case unexpectedStatus(OSStatus)
        case encodingError

        public var errorDescription: String? {
            switch self {
            case .itemNotFound:
                return "Item not found in Keychain"
            case .duplicateItem:
                return "Item already exists in Keychain"
            case .authenticationFailed:
                return "Pipeline could not unlock or read the saved API key from Keychain. Unlock your login keychain or re-save the API key in Settings."
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

    private func preferredServiceIdentifier() -> String {
        Constants.App.bundleID
    }

    private func serviceIdentifiersForLookup() -> [String] {
        [Constants.App.bundleID, Constants.App.legacyBundleID].uniquedPreservingOrder()
    }

    private func baseQuery(account: String, service: String, includeAccessGroup: Bool) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecAttrService as String: service,
        ]
        if includeAccessGroup {
            #if !targetEnvironment(simulator)
            query[kSecAttrAccessGroup as String] = KeychainService.accessGroup
            #endif
        }
        return query
    }

    private func readQueryVariants(for provider: AIProvider, account: String) -> [[String: Any]] {
        #if targetEnvironment(simulator)
        return serviceIdentifiersForLookup().map { service in
            baseQuery(account: account, service: service, includeAccessGroup: false)
        }
        #else
        return serviceIdentifiersForLookup().flatMap { service in
            [
                baseQuery(account: account, service: service, includeAccessGroup: true),
                baseQuery(account: account, service: service, includeAccessGroup: false)
            ]
        }
        #endif
    }

    private func writeQueryVariants(for provider: AIProvider, account: String) -> [[String: Any]] {
        #if targetEnvironment(simulator)
        return [baseQuery(account: account, service: preferredServiceIdentifier(), includeAccessGroup: false)]
        #else
        return [
            baseQuery(account: account, service: preferredServiceIdentifier(), includeAccessGroup: true),
            baseQuery(account: account, service: preferredServiceIdentifier(), includeAccessGroup: false)
        ]
        #endif
    }

    private func deleteQueryVariants(for provider: AIProvider, account: String) -> [[String: Any]] {
        readQueryVariants(for: provider, account: account)
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
        var lastAuthenticationFailure = false

        for baseQuery in readQueryVariants(for: provider, account: account) {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne

            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecItemNotFound {
                continue
            }

            if status == errSecAuthFailed {
                lastAuthenticationFailure = true
                continue
            }

            guard status == errSecSuccess else {
                throw KeychainError.unexpectedStatus(status)
            }

            guard let data = result as? Data else {
                throw KeychainError.encodingError
            }

            return data
        }

        if lastAuthenticationFailure {
            throw KeychainError.authenticationFailed
        }

        return nil
    }

    private func writeData(_ data: Data, for provider: AIProvider, account: String) throws {
        var lastStatus: OSStatus?

        for query in deleteQueryVariants(for: provider, account: account) {
            _ = SecItemDelete(query as CFDictionary)
        }

        for query in writeQueryVariants(for: provider, account: account) {
            _ = SecItemDelete(query as CFDictionary)

            var addQuery = query
            addQuery[kSecValueData as String] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecSuccess {
                return
            }

            lastStatus = status
            if !shouldFallbackFromGroupedKeychainStatus(status) {
                break
            }
        }

        if lastStatus == errSecAuthFailed {
            throw KeychainError.authenticationFailed
        }
        if let lastStatus {
            throw KeychainError.unexpectedStatus(lastStatus)
        }
    }

    private func deleteData(for provider: AIProvider, account: String) throws {
        var lastStatus: OSStatus = errSecSuccess
        var sawAuthenticationFailure = false

        for query in deleteQueryVariants(for: provider, account: account) {
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecSuccess || status == errSecItemNotFound {
                lastStatus = status
                continue
            }
            if status == errSecAuthFailed {
                sawAuthenticationFailure = true
                lastStatus = status
                continue
            }
            throw KeychainError.unexpectedStatus(status)
        }

        if sawAuthenticationFailure && lastStatus == errSecAuthFailed {
            throw KeychainError.authenticationFailed
        }
    }

    private func shouldFallbackFromGroupedKeychainStatus(_ status: OSStatus) -> Bool {
        status == errSecAuthFailed || status == errSecMissingEntitlement
    }

    public func hasAPIKey(for provider: AIProvider) -> Bool {
        do {
            return !(try getAPIKeys(for: provider)).isEmpty
        } catch {
            return false
        }
    }
}
