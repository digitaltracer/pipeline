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
        force: Bool
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
                modelContext: modelContext
            )
        } catch {
            try? persistFailure(
                message: error.localizedDescription,
                application: application,
                assessment: existingAssessment,
                resumeSource: resumeSource,
                modelContext: modelContext
            )
        }
    }

    private func persist(
        draft: ATSCompatibilityAssessmentDraft,
        application: JobApplication,
        assessment: ATSCompatibilityAssessment?,
        modelContext: ModelContext
    ) throws {
        let target = assessment ?? ATSCompatibilityAssessment()
        if assessment == nil {
            modelContext.insert(target)
            application.assignATSAssessment(target)
            target.application = application
        }

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
                criticalFindings: draft.criticalFindings,
                warningFindings: draft.warningFindings,
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

        try modelContext.save()
    }

    private func persistFailure(
        message: String,
        application: JobApplication,
        assessment: ATSCompatibilityAssessment?,
        resumeSource: ResumeSourceSelection?,
        modelContext: ModelContext
    ) throws {
        let target = assessment ?? ATSCompatibilityAssessment()
        if assessment == nil {
            modelContext.insert(target)
            application.assignATSAssessment(target)
            target.application = application
        }

        target.applyFailedState(
            resumeSourceKind: resumeSource.map { ATSResumeSourceKind(rawValue: $0.kind.rawValue) ?? .masterResume },
            resumeSourceSnapshotID: resumeSource?.snapshotID,
            resumeSourceRevisionID: resumeSource?.masterRevisionID,
            resumeSourceFingerprint: ATSCompatibilityScoringService.resumeSourceFingerprint(for: resumeSource),
            jobDescriptionHash: ATSCompatibilityScoringService.jobDescriptionHash(for: application),
            scoringVersion: ATSCompatibilityScoringService.scoringVersion,
            errorMessage: message
        )

        try modelContext.save()
    }
}
