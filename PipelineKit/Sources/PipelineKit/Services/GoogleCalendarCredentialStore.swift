import Foundation
import Security

struct GoogleOAuthCredentialBundle: Codable, Equatable {
    var googleUserID: String
    var email: String
    var displayName: String?
    var avatarURLString: String?
    var accessToken: String
    var refreshToken: String?
    var grantedScopes: [String]
    var lastUpdatedAt: Date
}

final class GoogleCalendarCredentialStore {
    static let shared = GoogleCalendarCredentialStore()

    private let account = "google.calendar.oauth.credentials"

    private init() {}

    func load() throws -> GoogleOAuthCredentialBundle? {
        guard let data = try readData() else { return nil }
        return try JSONDecoder().decode(GoogleOAuthCredentialBundle.self, from: data)
    }

    func save(_ credentials: GoogleOAuthCredentialBundle) throws {
        let data = try JSONEncoder().encode(credentials)
        try writeData(data)
    }

    func clear() throws {
        try deleteData()
    }

    private func preferredServiceIdentifier() -> String {
        Constants.App.bundleID
    }

    private func serviceIdentifiersForLookup() -> [String] {
        [Constants.App.bundleID, Constants.App.legacyBundleID].uniquedPreservingOrder()
    }

    private func baseQuery(service: String, includeAccessGroup: Bool) -> [String: Any] {
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

    private func readQueryVariants() -> [[String: Any]] {
        #if targetEnvironment(simulator)
        return serviceIdentifiersForLookup().map { service in
            baseQuery(service: service, includeAccessGroup: false)
        }
        #else
        return serviceIdentifiersForLookup().flatMap { service in
            [
                baseQuery(service: service, includeAccessGroup: true),
                baseQuery(service: service, includeAccessGroup: false)
            ]
        }
        #endif
    }

    private func writeQueryVariants() -> [[String: Any]] {
        #if targetEnvironment(simulator)
        return [baseQuery(service: preferredServiceIdentifier(), includeAccessGroup: false)]
        #else
        return [
            baseQuery(service: preferredServiceIdentifier(), includeAccessGroup: true),
            baseQuery(service: preferredServiceIdentifier(), includeAccessGroup: false)
        ]
        #endif
    }

    private func readData() throws -> Data? {
        var lastAuthenticationFailure = false

        for baseQuery in readQueryVariants() {
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
                throw KeychainService.KeychainError.unexpectedStatus(status)
            }

            guard let data = result as? Data else {
                throw KeychainService.KeychainError.encodingError
            }

            return data
        }

        if lastAuthenticationFailure {
            throw KeychainService.KeychainError.authenticationFailed
        }

        return nil
    }

    private func writeData(_ data: Data) throws {
        var lastStatus: OSStatus?

        for query in readQueryVariants() {
            _ = SecItemDelete(query as CFDictionary)
        }

        for query in writeQueryVariants() {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let status = SecItemAdd(addQuery as CFDictionary, nil)
            if status == errSecSuccess {
                return
            }

            lastStatus = status
            if status != errSecAuthFailed && status != errSecMissingEntitlement {
                break
            }
        }

        if lastStatus == errSecAuthFailed {
            throw KeychainService.KeychainError.authenticationFailed
        }

        if let lastStatus {
            throw KeychainService.KeychainError.unexpectedStatus(lastStatus)
        }
    }

    private func deleteData() throws {
        var lastStatus: OSStatus = errSecSuccess
        var sawAuthenticationFailure = false

        for query in readQueryVariants() {
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
            throw KeychainService.KeychainError.unexpectedStatus(status)
        }

        if sawAuthenticationFailure && lastStatus == errSecAuthFailed {
            throw KeychainService.KeychainError.authenticationFailed
        }
    }
}
