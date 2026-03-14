import Foundation
import GoogleSignIn
#if os(macOS)
import AppKit
#endif

enum GoogleOAuthServiceError: LocalizedError {
    case missingConfiguration
    case macOSOnly
    case missingPresentingWindow
    case noAuthenticatedUser
    case invalidTokenState

    public var errorDescription: String? {
        switch self {
        case .missingConfiguration:
            return "Google Calendar is not configured yet. Add GOOGLE_CLIENT_ID, GOOGLE_REVERSED_CLIENT_ID, and the matching callback URL scheme to the app configuration."
        case .macOSOnly:
            return "Google Calendar import currently ships on macOS only."
        case .missingPresentingWindow:
            return "Pipeline could not find a macOS window to present Google sign-in."
        case .noAuthenticatedUser:
            return "Google Calendar is not connected."
        case .invalidTokenState:
            return "Google sign-in completed, but Pipeline could not read the required access token."
        }
    }
}

@MainActor
final class GoogleOAuthService {
    static let shared = GoogleOAuthService()

    private let credentialStore = GoogleCalendarCredentialStore.shared

    private init() {}

    var isClientConfigured: Bool {
        GoogleCalendarConfiguration.isConfigured
    }

    func storedCredentials() -> GoogleOAuthCredentialBundle? {
        try? credentialStore.load()
    }

    func restorePreviousSession() async -> GoogleOAuthCredentialBundle? {
        guard isClientConfigured else {
            return storedCredentials()
        }

        configureIfPossible()

        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            let credentials = try await credentials(from: user, preservingRefreshToken: storedCredentials()?.refreshToken)
            try credentialStore.save(credentials)
            return credentials
        } catch {
            try? credentialStore.clear()
            return nil
        }
    }

    func signIn() async throws -> GoogleOAuthCredentialBundle {
        guard isClientConfigured else {
            throw GoogleOAuthServiceError.missingConfiguration
        }

        configureIfPossible()

        #if os(macOS)
        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: { $0.isVisible }) else {
            throw GoogleOAuthServiceError.missingPresentingWindow
        }

        let result = try await GIDSignIn.sharedInstance.signIn(
            withPresenting: window,
            hint: nil,
            additionalScopes: GoogleCalendarConfiguration.requiredScopes
        )

        let credentials = try await credentials(from: result.user, preservingRefreshToken: storedCredentials()?.refreshToken)
        try credentialStore.save(credentials)
        return credentials
        #else
        throw GoogleOAuthServiceError.macOSOnly
        #endif
    }

    func accessToken() async throws -> String {
        if let currentUser = GIDSignIn.sharedInstance.currentUser {
            let refreshedUser = try await currentUser.refreshTokensIfNeeded()
            let credentials = try await credentials(from: refreshedUser, preservingRefreshToken: storedCredentials()?.refreshToken)
            try credentialStore.save(credentials)
            return credentials.accessToken
        }

        if let restored = await restorePreviousSession() {
            return restored.accessToken
        }

        throw GoogleOAuthServiceError.noAuthenticatedUser
    }

    func disconnect() async {
        if GIDSignIn.sharedInstance.currentUser != nil {
            do {
                try await GIDSignIn.sharedInstance.disconnect()
            } catch {
                GIDSignIn.sharedInstance.signOut()
            }
        } else {
            GIDSignIn.sharedInstance.signOut()
        }

        try? credentialStore.clear()
    }

    private func configureIfPossible() {
        guard let clientID = GoogleCalendarConfiguration.clientID else { return }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
    }

    private func credentials(
        from user: GIDGoogleUser,
        preservingRefreshToken preservedRefreshToken: String?
    ) async throws -> GoogleOAuthCredentialBundle {
        let grantedScopes = (user.grantedScopes ?? []).uniquedPreservingOrder()
        let email = user.profile?.email ?? storedCredentials()?.email ?? ""
        let displayName = user.profile?.name ?? storedCredentials()?.displayName
        let avatarURLString = user.profile?.imageURL(withDimension: 96)?.absoluteString ?? storedCredentials()?.avatarURLString

        let accessToken = user.accessToken.tokenString
        guard !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw GoogleOAuthServiceError.invalidTokenState
        }

        let refreshToken = user.refreshToken.tokenString.nilIfBlank ?? preservedRefreshToken

        return GoogleOAuthCredentialBundle(
            googleUserID: user.userID ?? storedCredentials()?.googleUserID ?? email,
            email: email,
            displayName: displayName,
            avatarURLString: avatarURLString,
            accessToken: accessToken,
            refreshToken: refreshToken,
            grantedScopes: grantedScopes,
            lastUpdatedAt: Date()
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
