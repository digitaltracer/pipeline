import Foundation
import SwiftData

@Model
public final class DismissedAliasSuggestion {
    public var id: UUID = UUID()
    public var canonicalName: String = ""
    public var aliasName: String = ""
    public var normalizedCanonicalName: String = ""
    public var normalizedAliasName: String = ""
    public var dismissedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        canonicalName: String,
        aliasName: String,
        dismissedAt: Date = Date()
    ) {
        self.id = id
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliasName = aliasName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedCanonicalName = CompanyProfile.normalizedName(from: canonicalName)
        self.normalizedAliasName = CompanyProfile.normalizedName(from: aliasName)
        self.dismissedAt = dismissedAt
    }
}
