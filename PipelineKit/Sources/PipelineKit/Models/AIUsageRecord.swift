import Foundation
import SwiftData

public enum AIUsageFeature: String, Codable, CaseIterable, Sendable, Identifiable {
    case resumeTailoring = "resume_tailoring"
    case interviewPrep = "interview_prep"
    case followUpDraft = "follow_up_draft"
    case coverLetterDraft = "cover_letter_draft"
    case checklistSuggestions = "checklist_suggestions"
    case jobParsing = "job_parsing"
    case companyResearch = "company_research"
    case jobDescriptionDenoise = "job_description_denoise"
    case jobMatchScoring = "job_match_scoring"
    case resumeATSFixes = "resume_ats_fixes"
    case interviewLearnings = "interview_learnings"
    case rejectionLearnings = "rejection_learnings"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .resumeTailoring:
            return "Resume Tailoring"
        case .interviewPrep:
            return "Interview Prep"
        case .followUpDraft:
            return "Follow-up Draft"
        case .coverLetterDraft:
            return "Cover Letter Draft"
        case .checklistSuggestions:
            return "Checklist Suggestions"
        case .jobParsing:
            return "Job Parsing"
        case .companyResearch:
            return "Company Research"
        case .jobDescriptionDenoise:
            return "Job Description Denoise"
        case .jobMatchScoring:
            return "Job Match Scoring"
        case .resumeATSFixes:
            return "Resume ATS Fixes"
        case .interviewLearnings:
            return "Interview Learnings"
        case .rejectionLearnings:
            return "Rejection Learnings"
        }
    }
}

public enum AIUsageRequestStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case succeeded = "succeeded"
    case partial = "partial"
    case failed = "failed"

    public var id: String { rawValue }
}

@Model
public final class AIUsageRecord {
    public var id: UUID = UUID()
    public var featureRawValue: String = AIUsageFeature.resumeTailoring.rawValue
    public var providerID: String = ""
    public var model: String = ""
    public var requestStatusRawValue: String = AIUsageRequestStatus.succeeded.rawValue

    public var promptTokens: Int?
    public var completionTokens: Int?
    public var totalTokens: Int?

    public var inputCostUSD: Double?
    public var outputCostUSD: Double?
    public var totalCostUSD: Double?

    public var applicationID: UUID?
    public var companyID: UUID?
    public var startedAt: Date = Date()
    public var finishedAt: Date = Date()
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        feature: AIUsageFeature,
        providerID: String,
        model: String,
        requestStatus: AIUsageRequestStatus,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil,
        totalTokens: Int? = nil,
        inputCostUSD: Double? = nil,
        outputCostUSD: Double? = nil,
        totalCostUSD: Double? = nil,
        applicationID: UUID? = nil,
        companyID: UUID? = nil,
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        errorMessage: String? = nil
    ) {
        self.id = id
        self.featureRawValue = feature.rawValue
        self.providerID = providerID
        self.model = model
        self.requestStatusRawValue = requestStatus.rawValue
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.inputCostUSD = inputCostUSD
        self.outputCostUSD = outputCostUSD
        self.totalCostUSD = totalCostUSD
        self.applicationID = applicationID
        self.companyID = companyID
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.errorMessage = errorMessage
    }

    public var feature: AIUsageFeature {
        get { AIUsageFeature(rawValue: featureRawValue) ?? .resumeTailoring }
        set { featureRawValue = newValue.rawValue }
    }

    public var requestStatus: AIUsageRequestStatus {
        get { AIUsageRequestStatus(rawValue: requestStatusRawValue) ?? .succeeded }
        set { requestStatusRawValue = newValue.rawValue }
    }
}
