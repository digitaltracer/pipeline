import Foundation
import SwiftData

@Model
public final class Contact {
    public var id: UUID = UUID()
    public var fullName: String = ""
    public var email: String?
    public var phone: String?
    public var companyName: String?
    public var title: String?
    public var notes: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ApplicationContactLink.contact)
    public var applicationLinks: [ApplicationContactLink]?

    @Relationship(deleteRule: .nullify, inverse: \ApplicationActivity.contact)
    public var activities: [ApplicationActivity]?

    public init(
        id: UUID = UUID(),
        fullName: String,
        email: String? = nil,
        phone: String? = nil,
        companyName: String? = nil,
        title: String? = nil,
        notes: String? = nil,
        applicationLinks: [ApplicationContactLink]? = nil,
        activities: [ApplicationActivity]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.phone = phone
        self.companyName = companyName
        self.title = title
        self.notes = notes
        self.applicationLinks = applicationLinks
        self.activities = activities
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayCompanyName: String {
        companyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? companyName! : "Independent"
    }

    public var linkedApplications: [JobApplication] {
        let apps = (applicationLinks ?? []).compactMap(\.application)
        return apps.sorted { lhs, rhs in
            if lhs.updatedAt == rhs.updatedAt {
                return lhs.companyName.localizedCaseInsensitiveCompare(rhs.companyName) == .orderedAscending
            }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    public var sortedActivities: [ApplicationActivity] {
        (activities ?? []).sorted { $0.occurredAt > $1.occurredAt }
    }

    public var initials: String {
        let words = fullName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = words.joined().uppercased()
        return joined.isEmpty ? String(fullName.prefix(1)).uppercased() : joined
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public func mergeCompanyNameIfMissing(_ candidate: String?) {
        guard let candidate,
              !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              companyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        else { return }
        companyName = candidate
    }

    public static func normalizedLookupKey(name: String, companyName: String?) -> String? {
        let normalizedName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        guard !normalizedName.isEmpty else { return nil }

        let normalizedCompany = (companyName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        return "\(normalizedName)|\(normalizedCompany)"
    }
}
