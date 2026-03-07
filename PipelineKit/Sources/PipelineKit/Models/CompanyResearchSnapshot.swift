import Foundation
import SwiftData

@Model
public final class CompanyResearchSnapshot {
    public var id: UUID = UUID()
    public var providerID: String = ""
    public var model: String = ""
    public var requestStatusRawValue: String = AIUsageRequestStatus.succeeded.rawValue
    public var summaryText: String?
    public var rawResponseText: String?
    public var errorMessage: String?
    public var startedAt: Date = Date()
    public var finishedAt: Date = Date()
    public var applicationID: UUID?
    public var createdAt: Date = Date()

    public var company: CompanyProfile?

    @Relationship(deleteRule: .cascade, inverse: \CompanyResearchSource.snapshot)
    public var sources: [CompanyResearchSource]?

    @Relationship(deleteRule: .cascade, inverse: \CompanySalarySnapshot.snapshot)
    public var salarySnapshots: [CompanySalarySnapshot]?

    public init(
        id: UUID = UUID(),
        providerID: String,
        model: String,
        requestStatus: AIUsageRequestStatus,
        summaryText: String? = nil,
        rawResponseText: String? = nil,
        errorMessage: String? = nil,
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        applicationID: UUID? = nil,
        company: CompanyProfile? = nil,
        sources: [CompanyResearchSource]? = nil,
        salarySnapshots: [CompanySalarySnapshot]? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.providerID = providerID
        self.model = model
        self.requestStatusRawValue = requestStatus.rawValue
        self.summaryText = CompanyProfile.normalizedText(summaryText)
        self.rawResponseText = CompanyProfile.normalizedText(rawResponseText)
        self.errorMessage = CompanyProfile.normalizedText(errorMessage)
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.applicationID = applicationID
        self.company = company
        self.sources = sources
        self.salarySnapshots = salarySnapshots
        self.createdAt = createdAt
    }

    public var requestStatus: AIUsageRequestStatus {
        get { AIUsageRequestStatus(rawValue: requestStatusRawValue) ?? .succeeded }
        set { requestStatusRawValue = newValue.rawValue }
    }

    public var sortedSources: [CompanyResearchSource] {
        (sources ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    public var sortedSalarySnapshots: [CompanySalarySnapshot] {
        (salarySnapshots ?? []).sorted { lhs, rhs in
            if lhs.capturedAt != rhs.capturedAt {
                return lhs.capturedAt > rhs.capturedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }
}
