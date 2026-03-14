import Foundation
import GoogleSignIn

public enum GoogleCalendarConfiguration {
    public static let clientIDInfoKey = "GOOGLE_CLIENT_ID"
    public static let reversedClientIDInfoKey = "GOOGLE_REVERSED_CLIENT_ID"
    public static let bundleURLTypesInfoKey = "CFBundleURLTypes"
    public static let bundleURLSchemesInfoKey = "CFBundleURLSchemes"
    public static let calendarListReadonlyScope = "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
    public static let calendarEventsScope = "https://www.googleapis.com/auth/calendar.events"

    public static var requiredScopes: [String] {
        [calendarListReadonlyScope, calendarEventsScope]
    }

    public static var isConfigured: Bool {
        guard clientID != nil, let reversedClientID else {
            return false
        }

        let urlTypes = Bundle.main.object(forInfoDictionaryKey: bundleURLTypesInfoKey) as? [[String: Any]] ?? []
        return urlTypes.contains { type in
            let schemes = type[bundleURLSchemesInfoKey] as? [String] ?? []
            return schemes.contains(reversedClientID)
        }
    }

    public static var clientID: String? {
        infoString(for: clientIDInfoKey)
    }

    public static var reversedClientID: String? {
        infoString(for: reversedClientIDInfoKey)
    }

    public static func handleSignInURL(_ url: URL) -> Bool {
        GIDSignIn.sharedInstance.handle(url)
    }

    private static func infoString(for key: String) -> String? {
        let rawValue = Bundle.main.object(forInfoDictionaryKey: key) as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("$(") || !trimmed.hasSuffix(")") else { return nil }
        return trimmed
    }
}
