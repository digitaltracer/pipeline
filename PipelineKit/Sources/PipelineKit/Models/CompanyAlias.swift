import Foundation
import SwiftData

@Model
public final class CompanyAlias {
    public var id: UUID = UUID()
    public var canonicalName: String = ""
    public var aliasName: String = ""
    public var normalizedCanonicalName: String = ""
    public var normalizedAliasName: String = ""
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        canonicalName: String,
        aliasName: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliasName = aliasName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedCanonicalName = CompanyProfile.normalizedName(from: canonicalName)
        self.normalizedAliasName = CompanyProfile.normalizedName(from: aliasName)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func updateNames(canonicalName: String, aliasName: String) {
        self.canonicalName = canonicalName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliasName = aliasName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedCanonicalName = CompanyProfile.normalizedName(from: canonicalName)
        self.normalizedAliasName = CompanyProfile.normalizedName(from: aliasName)
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
