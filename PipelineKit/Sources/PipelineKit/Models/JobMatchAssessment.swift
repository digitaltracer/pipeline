import Foundation
import SwiftData

@Model
public final class JobMatchAssessment {
    public var id: UUID = UUID()
    public var overallScore: Int?
    public var skillsScore: Int?
    public var experienceScore: Int?
    public var salaryScore: Int?
    public var locationScore: Int?
    public var matchedSkills: [String] = []
    public var missingSkills: [String] = []
    public var summary: String?
    public var gapAnalysis: String?
    public private(set) var statusRawValue: String = JobMatchAssessmentStatus.blocked.rawValue
    public private(set) var blockedReasonRawValue: String?
    public var resumeRevisionID: UUID?
    public var jobDescriptionHash: String?
    public var preferencesFingerprint: String?
    public var scoringVersion: String = ""
    public var lastErrorMessage: String?
    public var scoredAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public init(
        id: UUID = UUID(),
        overallScore: Int? = nil,
        skillsScore: Int? = nil,
        experienceScore: Int? = nil,
        salaryScore: Int? = nil,
        locationScore: Int? = nil,
        matchedSkills: [String] = [],
        missingSkills: [String] = [],
        summary: String? = nil,
        gapAnalysis: String? = nil,
        status: JobMatchAssessmentStatus = .blocked,
        blockedReason: JobMatchBlockedReason? = nil,
        resumeRevisionID: UUID? = nil,
        jobDescriptionHash: String? = nil,
        preferencesFingerprint: String? = nil,
        scoringVersion: String = "",
        lastErrorMessage: String? = nil,
        scoredAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.overallScore = overallScore
        self.skillsScore = skillsScore
        self.experienceScore = experienceScore
        self.salaryScore = salaryScore
        self.locationScore = locationScore
        self.matchedSkills = matchedSkills
        self.missingSkills = missingSkills
        self.summary = summary
        self.gapAnalysis = gapAnalysis
        self.statusRawValue = status.rawValue
        self.blockedReasonRawValue = blockedReason?.rawValue
        self.resumeRevisionID = resumeRevisionID
        self.jobDescriptionHash = jobDescriptionHash
        self.preferencesFingerprint = preferencesFingerprint
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = lastErrorMessage
        self.scoredAt = scoredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var status: JobMatchAssessmentStatus {
        get { JobMatchAssessmentStatus(rawValue: statusRawValue) ?? .blocked }
        set {
            guard statusRawValue != newValue.rawValue else { return }
            statusRawValue = newValue.rawValue
            touch()
        }
    }

    public var blockedReason: JobMatchBlockedReason? {
        get {
            guard let blockedReasonRawValue else { return nil }
            return JobMatchBlockedReason(rawValue: blockedReasonRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard blockedReasonRawValue != newRawValue else { return }
            blockedReasonRawValue = newRawValue
            touch()
        }
    }

    public var formattedOverallScore: String? {
        guard let overallScore else { return nil }
        return "\(overallScore)%"
    }

    public func applyReadyState(
        overallScore: Int?,
        skillsScore: Int?,
        experienceScore: Int?,
        salaryScore: Int?,
        locationScore: Int?,
        matchedSkills: [String],
        missingSkills: [String],
        summary: String?,
        gapAnalysis: String?,
        resumeRevisionID: UUID?,
        jobDescriptionHash: String?,
        preferencesFingerprint: String?,
        scoringVersion: String,
        scoredAt: Date,
        lastErrorMessage: String? = nil
    ) {
        self.overallScore = overallScore
        self.skillsScore = skillsScore
        self.experienceScore = experienceScore
        self.salaryScore = salaryScore
        self.locationScore = locationScore
        self.matchedSkills = matchedSkills
        self.missingSkills = missingSkills
        self.summary = summary
        self.gapAnalysis = gapAnalysis
        self.resumeRevisionID = resumeRevisionID
        self.jobDescriptionHash = jobDescriptionHash
        self.preferencesFingerprint = preferencesFingerprint
        self.scoringVersion = scoringVersion
        self.scoredAt = scoredAt
        self.lastErrorMessage = lastErrorMessage
        self.statusRawValue = JobMatchAssessmentStatus.ready.rawValue
        self.blockedReasonRawValue = nil
        touch()
    }

    public func applyBlockedState(
        reason: JobMatchBlockedReason,
        resumeRevisionID: UUID?,
        jobDescriptionHash: String?,
        preferencesFingerprint: String?,
        scoringVersion: String,
        message: String? = nil
    ) {
        overallScore = nil
        skillsScore = nil
        experienceScore = nil
        salaryScore = nil
        locationScore = nil
        matchedSkills = []
        missingSkills = []
        summary = nil
        gapAnalysis = nil
        statusRawValue = JobMatchAssessmentStatus.blocked.rawValue
        blockedReasonRawValue = reason.rawValue
        self.resumeRevisionID = resumeRevisionID
        self.jobDescriptionHash = jobDescriptionHash
        self.preferencesFingerprint = preferencesFingerprint
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = message
        self.scoredAt = Date()
        touch()
    }

    public func applyFailedState(
        resumeRevisionID: UUID?,
        jobDescriptionHash: String?,
        preferencesFingerprint: String?,
        scoringVersion: String,
        errorMessage: String
    ) {
        overallScore = nil
        skillsScore = nil
        experienceScore = nil
        salaryScore = nil
        locationScore = nil
        matchedSkills = []
        missingSkills = []
        summary = nil
        gapAnalysis = nil
        statusRawValue = JobMatchAssessmentStatus.failed.rawValue
        blockedReasonRawValue = nil
        self.resumeRevisionID = resumeRevisionID
        self.jobDescriptionHash = jobDescriptionHash
        self.preferencesFingerprint = preferencesFingerprint
        self.scoringVersion = scoringVersion
        lastErrorMessage = errorMessage
        scoredAt = Date()
        touch()
    }

    public func touch() {
        updatedAt = Date()
    }
}
