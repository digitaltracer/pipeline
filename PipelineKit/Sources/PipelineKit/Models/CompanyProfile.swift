import Foundation
import SwiftData

@Model
public final class CompanyProfile {
    public var id: UUID = UUID()
    public var name: String = ""
    public var normalizedName: String = ""
    public var websiteURL: String?
    public var linkedInURL: String?
    public var glassdoorURL: String?
    public var levelsFYIURL: String?
    public var teamBlindURL: String?
    public var industry: String?
    private var sizeBandRawValue: String?
    public var headquarters: String?
    public var userRating: Int?
    public var notesMarkdown: String?
    public var lastResearchSummary: String?
    public var lastResearchedAt: Date?
    public var lastSalaryResearchAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \JobApplication.company)
    public var applications: [JobApplication]?

    @Relationship(deleteRule: .cascade, inverse: \CompanyResearchSnapshot.company)
    public var researchSnapshots: [CompanyResearchSnapshot]?

    @Relationship(deleteRule: .cascade, inverse: \CompanyResearchSource.company)
    public var researchSources: [CompanyResearchSource]?

    @Relationship(deleteRule: .cascade, inverse: \CompanySalarySnapshot.company)
    public var salarySnapshots: [CompanySalarySnapshot]?

    public init(
        id: UUID = UUID(),
        name: String,
        websiteURL: String? = nil,
        linkedInURL: String? = nil,
        glassdoorURL: String? = nil,
        levelsFYIURL: String? = nil,
        teamBlindURL: String? = nil,
        industry: String? = nil,
        sizeBand: CompanySizeBand? = nil,
        headquarters: String? = nil,
        userRating: Int? = nil,
        notesMarkdown: String? = nil,
        lastResearchSummary: String? = nil,
        lastResearchedAt: Date? = nil,
        lastSalaryResearchAt: Date? = nil,
        applications: [JobApplication]? = nil,
        researchSnapshots: [CompanyResearchSnapshot]? = nil,
        researchSources: [CompanyResearchSource]? = nil,
        salarySnapshots: [CompanySalarySnapshot]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.normalizedName = Self.normalizedName(from: name)
        self.websiteURL = Self.normalizedURLString(websiteURL)
        self.linkedInURL = Self.normalizedURLString(linkedInURL)
        self.glassdoorURL = Self.normalizedURLString(glassdoorURL)
        self.levelsFYIURL = Self.normalizedURLString(levelsFYIURL)
        self.teamBlindURL = Self.normalizedURLString(teamBlindURL)
        self.industry = Self.normalizedText(industry)
        self.sizeBandRawValue = sizeBand?.rawValue
        self.headquarters = Self.normalizedText(headquarters)
        self.userRating = Self.clampedRating(userRating)
        self.notesMarkdown = Self.normalizedText(notesMarkdown)
        self.lastResearchSummary = Self.normalizedText(lastResearchSummary)
        self.lastResearchedAt = lastResearchedAt
        self.lastSalaryResearchAt = lastSalaryResearchAt
        self.applications = applications
        self.researchSnapshots = researchSnapshots
        self.researchSources = researchSources
        self.salarySnapshots = salarySnapshots
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sizeBand: CompanySizeBand? {
        get {
            guard let sizeBandRawValue,
                  !sizeBandRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return CompanySizeBand(rawValue: sizeBandRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard sizeBandRawValue != newRawValue else { return }
            sizeBandRawValue = newRawValue
            updateTimestamp()
        }
    }

    public var sortedApplications: [JobApplication] {
        (applications ?? []).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.role.localizedCaseInsensitiveCompare(rhs.role) == .orderedAscending
        }
    }

    public var sortedResearchSnapshots: [CompanyResearchSnapshot] {
        (researchSnapshots ?? []).sorted { lhs, rhs in
            if lhs.finishedAt != rhs.finishedAt {
                return lhs.finishedAt > rhs.finishedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var sortedResearchSources: [CompanyResearchSource] {
        (researchSources ?? []).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.orderIndex < rhs.orderIndex
        }
    }

    public var sortedSalarySnapshots: [CompanySalarySnapshot] {
        (salarySnapshots ?? []).sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var sourceLinks: [String] {
        [
            websiteURL,
            linkedInURL,
            glassdoorURL,
            levelsFYIURL,
            teamBlindURL
        ]
        .compactMap { Self.normalizedURLString($0) }
        .uniquedPreservingOrder()
    }

    public func rename(_ value: String) {
        let normalized = Self.normalizedText(value) ?? name
        guard !normalized.isEmpty else { return }
        name = normalized
        normalizedName = Self.normalizedName(from: normalized)
        updateTimestamp()
    }

    public func setWebsiteURL(_ value: String?) {
        websiteURL = Self.normalizedURLString(value)
        updateTimestamp()
    }

    public func setLinkedInURL(_ value: String?) {
        linkedInURL = Self.normalizedURLString(value)
        updateTimestamp()
    }

    public func setGlassdoorURL(_ value: String?) {
        glassdoorURL = Self.normalizedURLString(value)
        updateTimestamp()
    }

    public func setLevelsFYIURL(_ value: String?) {
        levelsFYIURL = Self.normalizedURLString(value)
        updateTimestamp()
    }

    public func setTeamBlindURL(_ value: String?) {
        teamBlindURL = Self.normalizedURLString(value)
        updateTimestamp()
    }

    public func setIndustry(_ value: String?) {
        industry = Self.normalizedText(value)
        updateTimestamp()
    }

    public func setHeadquarters(_ value: String?) {
        headquarters = Self.normalizedText(value)
        updateTimestamp()
    }

    public func setUserRating(_ value: Int?) {
        userRating = Self.clampedRating(value)
        updateTimestamp()
    }

    public func setNotesMarkdown(_ value: String?) {
        notesMarkdown = Self.normalizedText(value)
        updateTimestamp()
    }

    public func setLastResearchSummary(_ value: String?) {
        lastResearchSummary = Self.normalizedText(value)
        updateTimestamp()
    }

    public func touchResearch(at date: Date = Date(), summary: String?) {
        lastResearchSummary = Self.normalizedText(summary) ?? lastResearchSummary
        lastResearchedAt = date
        updateTimestamp()
    }

    public func touchSalaryResearch(at date: Date = Date()) {
        lastSalaryResearchAt = date
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public static func normalizedName(from value: String) -> String {
        let lowered = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "&", with: " and ")
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\b(incorporated|corporation|corp|inc|llc|ltd|limited|co|company|technologies|technology)\\b", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return lowered
    }

    public static func normalizedRoleTitle(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedLocation(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func normalizedURLString(_ value: String?) -> String? {
        guard let value = normalizedText(value) else { return nil }
        let normalized = URLHelpers.normalize(value)
        guard URLHelpers.isValidWebURL(normalized) else { return nil }
        return normalized
    }

    private static func clampedRating(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return min(max(value, 1), 5)
    }
}
