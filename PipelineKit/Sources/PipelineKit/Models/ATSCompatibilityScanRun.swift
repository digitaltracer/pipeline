import Foundation
import SwiftData

@Model
public final class ATSCompatibilityScanRun {
    public var id: UUID = UUID()
    public var overallScore: Int?
    public var keywordScore: Int?
    public var sectionScore: Int?
    public var contactScore: Int?
    public var formatScore: Int?
    public var summary: String?
    public var matchedKeywords: [String] = []
    public var missingKeywords: [String] = []
    public var skillsPromotionKeywords: [String] = []
    public var keywordEvidenceSummary: [String] = []
    public var criticalFindings: [String] = []
    public var warningFindings: [String] = []
    public var sectionFindings: [String] = []
    public var contactWarningFindings: [String] = []
    public var contactCriticalFindings: [String] = []
    public var formatWarningFindings: [String] = []
    public var formatCriticalFindings: [String] = []
    public var hasExperienceSection: Bool = false
    public var hasEducationSection: Bool = false
    public var hasSkillsSection: Bool = false
    public private(set) var statusRawValue: String = ATSAssessmentStatus.blocked.rawValue
    public private(set) var blockedReasonRawValue: String?
    public private(set) var resumeSourceKindRawValue: String?
    public private(set) var scanTriggerRawValue: String = ATSScanTrigger.autoViewRefresh.rawValue
    public var resumeSourceSnapshotID: UUID?
    public var resumeSourceRevisionID: UUID?
    public var resumeSourceFingerprint: String?
    public var jobDescriptionHash: String?
    public var scoringVersion: String = ""
    public var lastErrorMessage: String?
    public var scoredAt: Date?
    public var createdAt: Date = Date()

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
        skillsPromotionKeywords: [String] = [],
        keywordEvidenceSummary: [String] = [],
        criticalFindings: [String] = [],
        warningFindings: [String] = [],
        sectionFindings: [String] = [],
        contactWarningFindings: [String] = [],
        contactCriticalFindings: [String] = [],
        formatWarningFindings: [String] = [],
        formatCriticalFindings: [String] = [],
        hasExperienceSection: Bool = false,
        hasEducationSection: Bool = false,
        hasSkillsSection: Bool = false,
        status: ATSAssessmentStatus = .blocked,
        blockedReason: ATSBlockedReason? = nil,
        resumeSourceKind: ATSResumeSourceKind? = nil,
        scanTrigger: ATSScanTrigger = .autoViewRefresh,
        resumeSourceSnapshotID: UUID? = nil,
        resumeSourceRevisionID: UUID? = nil,
        resumeSourceFingerprint: String? = nil,
        jobDescriptionHash: String? = nil,
        scoringVersion: String = "",
        lastErrorMessage: String? = nil,
        scoredAt: Date? = nil,
        createdAt: Date = Date()
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
        self.skillsPromotionKeywords = skillsPromotionKeywords
        self.keywordEvidenceSummary = keywordEvidenceSummary
        self.criticalFindings = criticalFindings
        self.warningFindings = warningFindings
        self.sectionFindings = sectionFindings
        self.contactWarningFindings = contactWarningFindings
        self.contactCriticalFindings = contactCriticalFindings
        self.formatWarningFindings = formatWarningFindings
        self.formatCriticalFindings = formatCriticalFindings
        self.hasExperienceSection = hasExperienceSection
        self.hasEducationSection = hasEducationSection
        self.hasSkillsSection = hasSkillsSection
        self.statusRawValue = status.rawValue
        self.blockedReasonRawValue = blockedReason?.rawValue
        self.resumeSourceKindRawValue = resumeSourceKind?.rawValue
        self.scanTriggerRawValue = scanTrigger.rawValue
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        self.lastErrorMessage = lastErrorMessage
        self.scoredAt = scoredAt
        self.createdAt = createdAt
    }

    public var status: ATSAssessmentStatus {
        ATSAssessmentStatus(rawValue: statusRawValue) ?? .blocked
    }

    public var blockedReason: ATSBlockedReason? {
        guard let blockedReasonRawValue else { return nil }
        return ATSBlockedReason(rawValue: blockedReasonRawValue)
    }

    public var resumeSourceKind: ATSResumeSourceKind? {
        guard let resumeSourceKindRawValue else { return nil }
        return ATSResumeSourceKind(rawValue: resumeSourceKindRawValue)
    }

    public var scanTrigger: ATSScanTrigger {
        ATSScanTrigger(rawValue: scanTriggerRawValue) ?? .autoViewRefresh
    }
}
