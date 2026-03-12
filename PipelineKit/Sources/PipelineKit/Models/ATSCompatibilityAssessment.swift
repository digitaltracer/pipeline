import Foundation
import SwiftData

@Model
public final class ATSCompatibilityAssessment {
    public var id: UUID = UUID()
    public var overallScore: Int?
    public var keywordScore: Int?
    public var sectionScore: Int?
    public var contactScore: Int?
    public var formatScore: Int?
    public var summary: String?
    public var matchedKeywords: [String] = []
    public var missingKeywords: [String] = []
    public var criticalFindings: [String] = []
    public var warningFindings: [String] = []
    public private(set) var statusRawValue: String = ATSAssessmentStatus.blocked.rawValue
    public private(set) var blockedReasonRawValue: String?
    public private(set) var resumeSourceKindRawValue: String?
    public var resumeSourceSnapshotID: UUID?
    public var resumeSourceRevisionID: UUID?
    public var resumeSourceFingerprint: String?
    public var jobDescriptionHash: String?
    public var scoringVersion: String = ""
    public var lastErrorMessage: String?
    public var scoredAt: Date?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public init(
        id: UUID = UUID(),
        overallScore: Int? = nil,
        keywordScore: Int? = nil,
        sectionScore: Int? = nil,
        contactScore: Int? = nil,
        formatScore: Int? = nil,
        summary: String? = nil,
        matchedKeywords: [String] = [],
        missingKeywords: [String] = [],
        criticalFindings: [String] = [],
        warningFindings: [String] = [],
        status: ATSAssessmentStatus = .blocked,
        blockedReason: ATSBlockedReason? = nil,
        resumeSourceKind: ATSResumeSourceKind? = nil,
        resumeSourceSnapshotID: UUID? = nil,
        resumeSourceRevisionID: UUID? = nil,
        resumeSourceFingerprint: String? = nil,
        jobDescriptionHash: String? = nil,
        scoringVersion: String = "",
        lastErrorMessage: String? = nil,
        scoredAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.overallScore = overallScore
        self.keywordScore = keywordScore
        self.sectionScore = sectionScore
        self.contactScore = contactScore
        self.formatScore = formatScore
        self.summary = summary
        self.matchedKeywords = matchedKeywords
        self.missingKeywords = missingKeywords
        self.criticalFindings = criticalFindings
        self.warningFindings = warningFindings
        self.statusRawValue = status.rawValue
        self.blockedReasonRawValue = blockedReason?.rawValue
        self.resumeSourceKindRawValue = resumeSourceKind?.rawValue
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = lastErrorMessage
        self.scoredAt = scoredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var status: ATSAssessmentStatus {
        get { ATSAssessmentStatus(rawValue: statusRawValue) ?? .blocked }
        set {
            guard statusRawValue != newValue.rawValue else { return }
            statusRawValue = newValue.rawValue
            touch()
        }
    }

    public var blockedReason: ATSBlockedReason? {
        get {
            guard let blockedReasonRawValue else { return nil }
            return ATSBlockedReason(rawValue: blockedReasonRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard blockedReasonRawValue != newRawValue else { return }
            blockedReasonRawValue = newRawValue
            touch()
        }
    }

    public var resumeSourceKind: ATSResumeSourceKind? {
        get {
            guard let resumeSourceKindRawValue else { return nil }
            return ATSResumeSourceKind(rawValue: resumeSourceKindRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard resumeSourceKindRawValue != newRawValue else { return }
            resumeSourceKindRawValue = newRawValue
            touch()
        }
    }

    public var formattedOverallScore: String? {
        guard let overallScore else { return nil }
        return "\(overallScore)%"
    }

    public func applyReadyState(
        overallScore: Int,
        keywordScore: Int,
        sectionScore: Int,
        contactScore: Int,
        formatScore: Int,
        summary: String,
        matchedKeywords: [String],
        missingKeywords: [String],
        criticalFindings: [String],
        warningFindings: [String],
        resumeSourceKind: ATSResumeSourceKind,
        resumeSourceSnapshotID: UUID?,
        resumeSourceRevisionID: UUID?,
        resumeSourceFingerprint: String?,
        jobDescriptionHash: String?,
        scoringVersion: String,
        scoredAt: Date,
        lastErrorMessage: String? = nil
    ) {
        self.overallScore = overallScore
        self.keywordScore = keywordScore
        self.sectionScore = sectionScore
        self.contactScore = contactScore
        self.formatScore = formatScore
        self.summary = summary
        self.matchedKeywords = matchedKeywords
        self.missingKeywords = missingKeywords
        self.criticalFindings = criticalFindings
        self.warningFindings = warningFindings
        self.resumeSourceKindRawValue = resumeSourceKind.rawValue
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = lastErrorMessage
        self.scoredAt = scoredAt
        self.statusRawValue = ATSAssessmentStatus.ready.rawValue
        self.blockedReasonRawValue = nil
        touch()
    }

    public func applyBlockedState(
        reason: ATSBlockedReason,
        resumeSourceKind: ATSResumeSourceKind?,
        resumeSourceSnapshotID: UUID?,
        resumeSourceRevisionID: UUID?,
        resumeSourceFingerprint: String?,
        jobDescriptionHash: String?,
        scoringVersion: String,
        message: String? = nil
    ) {
        overallScore = nil
        keywordScore = nil
        sectionScore = nil
        contactScore = nil
        formatScore = nil
        summary = nil
        matchedKeywords = []
        missingKeywords = []
        criticalFindings = []
        warningFindings = []
        statusRawValue = ATSAssessmentStatus.blocked.rawValue
        blockedReasonRawValue = reason.rawValue
        resumeSourceKindRawValue = resumeSourceKind?.rawValue
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = message
        self.scoredAt = Date()
        touch()
    }

    public func applyFailedState(
        resumeSourceKind: ATSResumeSourceKind?,
        resumeSourceSnapshotID: UUID?,
        resumeSourceRevisionID: UUID?,
        resumeSourceFingerprint: String?,
        jobDescriptionHash: String?,
        scoringVersion: String,
        errorMessage: String
    ) {
        overallScore = nil
        keywordScore = nil
        sectionScore = nil
        contactScore = nil
        formatScore = nil
        summary = nil
        matchedKeywords = []
        missingKeywords = []
        criticalFindings = []
        warningFindings = []
        statusRawValue = ATSAssessmentStatus.failed.rawValue
        blockedReasonRawValue = nil
        resumeSourceKindRawValue = resumeSourceKind?.rawValue
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        lastErrorMessage = errorMessage
        scoredAt = Date()
        touch()
    }

    public func touch() {
        updatedAt = Date()
    }
}
