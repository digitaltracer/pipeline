import Foundation
import SwiftData
import PipelineKit

@MainActor
final class ATSCompatibilityCoordinator {
    static let shared = ATSCompatibilityCoordinator()

    private var processingApplicationIDs: Set<UUID> = []

    private init() {}

    func refresh(
        application: JobApplication,
        modelContext: ModelContext,
        force: Bool,
        trigger: ATSScanTrigger = .autoViewRefresh
    ) async {
        guard !processingApplicationIDs.contains(application.id) else { return }
        processingApplicationIDs.insert(application.id)
        defer { processingApplicationIDs.remove(application.id) }

        let existingAssessment = application.atsAssessment
        let resumeSource = try? ResumeStoreService.preferredResumeSource(
            for: application,
            in: modelContext
        )

        if !force,
           let existingAssessment,
           existingAssessment.status == .ready,
           !ATSCompatibilityScoringService.isStale(
            existingAssessment,
            application: application,
            resumeSource: resumeSource
           ) {
            return
        }

        do {
            let draft = try ATSCompatibilityScoringService.prepareDraft(
                application: application,
                resumeSource: resumeSource
            )
            try persist(
                draft: draft,
                application: application,
                assessment: existingAssessment,
                modelContext: modelContext,
                trigger: trigger
            )
        } catch {
            let draft = failureDraft(
                message: error.localizedDescription,
                application: application,
                resumeSource: resumeSource
            )
            try? persist(
                draft: draft,
                application: application,
                assessment: existingAssessment,
                modelContext: modelContext,
                trigger: trigger
            )
        }
    }

    private func persist(
        draft: ATSCompatibilityAssessmentDraft,
        application: JobApplication,
        assessment: ATSCompatibilityAssessment?,
        modelContext: ModelContext,
        trigger: ATSScanTrigger = .autoViewRefresh
    ) throws {
        let target = assessment ?? ATSCompatibilityAssessment()
        if assessment == nil {
            modelContext.insert(target)
            application.assignATSAssessment(target)
            target.application = application
        }

        let shouldAppendRun = !(assessment?.isEquivalent(to: draft) ?? false)

        switch draft.status {
        case .ready:
            target.applyReadyState(
                overallScore: draft.overallScore ?? 0,
                keywordScore: draft.keywordScore ?? 0,
                sectionScore: draft.sectionScore ?? 0,
                contactScore: draft.contactScore ?? 0,
                formatScore: draft.formatScore ?? 0,
                summary: draft.summary ?? "",
                matchedKeywords: draft.matchedKeywords,
                missingKeywords: draft.missingKeywords,
                skillsPromotionKeywords: draft.skillsPromotionKeywords,
                keywordEvidenceSummary: draft.keywordEvidenceSummary,
                criticalFindings: draft.criticalFindings,
                warningFindings: draft.warningFindings,
                sectionFindings: draft.sectionFindings,
                contactWarningFindings: draft.contactWarningFindings,
                contactCriticalFindings: draft.contactCriticalFindings,
                formatWarningFindings: draft.formatWarningFindings,
                formatCriticalFindings: draft.formatCriticalFindings,
                hasExperienceSection: draft.hasExperienceSection,
                hasEducationSection: draft.hasEducationSection,
                hasSkillsSection: draft.hasSkillsSection,
                resumeSourceKind: draft.resumeSourceKind ?? .masterResume,
                resumeSourceSnapshotID: draft.resumeSourceSnapshotID,
                resumeSourceRevisionID: draft.resumeSourceRevisionID,
                resumeSourceFingerprint: draft.resumeSourceFingerprint,
                jobDescriptionHash: draft.jobDescriptionHash,
                scoringVersion: draft.scoringVersion,
                scoredAt: draft.scoredAt,
                lastErrorMessage: nil
            )
        case .blocked:
            target.applyBlockedState(
                reason: draft.blockedReason ?? .missingResumeSource,
                resumeSourceKind: draft.resumeSourceKind,
                resumeSourceSnapshotID: draft.resumeSourceSnapshotID,
                resumeSourceRevisionID: draft.resumeSourceRevisionID,
                resumeSourceFingerprint: draft.resumeSourceFingerprint,
                jobDescriptionHash: draft.jobDescriptionHash,
                scoringVersion: draft.scoringVersion,
                message: draft.lastErrorMessage
            )
        case .failed:
            target.applyFailedState(
                resumeSourceKind: draft.resumeSourceKind,
                resumeSourceSnapshotID: draft.resumeSourceSnapshotID,
                resumeSourceRevisionID: draft.resumeSourceRevisionID,
                resumeSourceFingerprint: draft.resumeSourceFingerprint,
                jobDescriptionHash: draft.jobDescriptionHash,
                scoringVersion: draft.scoringVersion,
                errorMessage: draft.lastErrorMessage ?? "ATS compatibility scoring failed."
            )
        }

        if shouldAppendRun {
            let run = ATSCompatibilityScanRun(
                overallScore: draft.overallScore,
                keywordScore: draft.keywordScore,
                sectionScore: draft.sectionScore,
                contactScore: draft.contactScore,
                formatScore: draft.formatScore,
                summary: draft.summary,
                matchedKeywords: draft.matchedKeywords,
                missingKeywords: draft.missingKeywords,
                skillsPromotionKeywords: draft.skillsPromotionKeywords,
                keywordEvidenceSummary: draft.keywordEvidenceSummary,
                criticalFindings: draft.criticalFindings,
                warningFindings: draft.warningFindings,
                sectionFindings: draft.sectionFindings,
                contactWarningFindings: draft.contactWarningFindings,
                contactCriticalFindings: draft.contactCriticalFindings,
                formatWarningFindings: draft.formatWarningFindings,
                formatCriticalFindings: draft.formatCriticalFindings,
                hasExperienceSection: draft.hasExperienceSection,
                hasEducationSection: draft.hasEducationSection,
                hasSkillsSection: draft.hasSkillsSection,
                status: draft.status,
                blockedReason: draft.blockedReason,
                resumeSourceKind: draft.resumeSourceKind,
                scanTrigger: trigger,
                resumeSourceSnapshotID: draft.resumeSourceSnapshotID,
                resumeSourceRevisionID: draft.resumeSourceRevisionID,
                resumeSourceFingerprint: draft.resumeSourceFingerprint,
                jobDescriptionHash: draft.jobDescriptionHash,
                scoringVersion: draft.scoringVersion,
                lastErrorMessage: draft.lastErrorMessage,
                scoredAt: draft.scoredAt
            )
            run.application = application
            application.addATSScanRun(run)
            modelContext.insert(run)
        }

        try modelContext.save()
    }

    private func failureDraft(
        message: String,
        application: JobApplication,
        resumeSource: ResumeSourceSelection?
    ) -> ATSCompatibilityAssessmentDraft {
        ATSCompatibilityAssessmentDraft(
            overallScore: nil,
            keywordScore: nil,
            sectionScore: nil,
            contactScore: nil,
            formatScore: nil,
            summary: nil,
            matchedKeywords: [],
            missingKeywords: [],
            skillsPromotionKeywords: [],
            keywordEvidenceSummary: [],
            criticalFindings: [],
            warningFindings: [],
            sectionFindings: [],
            contactWarningFindings: [],
            contactCriticalFindings: [],
            formatWarningFindings: [],
            formatCriticalFindings: [],
            hasExperienceSection: false,
            hasEducationSection: false,
            hasSkillsSection: false,
            status: .failed,
            blockedReason: nil,
            resumeSourceKind: resumeSource.map { ATSResumeSourceKind(rawValue: $0.kind.rawValue) ?? .masterResume },
            resumeSourceSnapshotID: resumeSource?.snapshotID,
            resumeSourceRevisionID: resumeSource?.masterRevisionID,
            resumeSourceFingerprint: ATSCompatibilityScoringService.resumeSourceFingerprint(for: resumeSource),
            lastErrorMessage: message,
            jobDescriptionHash: ATSCompatibilityScoringService.jobDescriptionHash(for: application),
            scoringVersion: ATSCompatibilityScoringService.scoringVersion,
            scoredAt: Date()
        )
    }
}
