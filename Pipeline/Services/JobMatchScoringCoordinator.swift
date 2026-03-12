import Foundation
import SwiftData
import PipelineKit

@MainActor
final class JobMatchScoringCoordinator {
    static let shared = JobMatchScoringCoordinator()

    private var processingApplicationIDs: Set<UUID> = []

    private init() {}

    func processEligibleApplications(
        _ applications: [JobApplication],
        modelContext: ModelContext,
        settingsViewModel: SettingsViewModel
    ) async {
        let currentResumeRevision = try? ResumeStoreService.currentMasterRevision(in: modelContext)
        let currentResumeRevisionID = currentResumeRevision?.id
        let preferences = settingsViewModel.jobMatchPreferences

        for application in applications {
            if application.matchAssessment == nil {
                await refresh(
                    application: application,
                    modelContext: modelContext,
                    settingsViewModel: settingsViewModel,
                    currentResumeRevision: currentResumeRevision,
                    force: true
                )
                continue
            }

            guard let assessment = application.matchAssessment else { continue }
            guard JobMatchScoringService.shouldAutoRefresh(
                assessment,
                application: application,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: preferences
            ) else {
                continue
            }

            await refresh(
                application: application,
                modelContext: modelContext,
                settingsViewModel: settingsViewModel,
                currentResumeRevision: currentResumeRevision,
                force: true
            )
        }
    }

    func refreshAllStaleApplications(
        _ applications: [JobApplication],
        modelContext: ModelContext,
        settingsViewModel: SettingsViewModel
    ) async {
        let currentResumeRevision = try? ResumeStoreService.currentMasterRevision(in: modelContext)
        let preferences = settingsViewModel.jobMatchPreferences

        for application in applications {
            guard let assessment = application.matchAssessment else { continue }
            guard JobMatchScoringService.isStale(
                assessment,
                application: application,
                currentResumeRevisionID: currentResumeRevision?.id,
                preferences: preferences
            ) else {
                continue
            }

            await refresh(
                application: application,
                modelContext: modelContext,
                settingsViewModel: settingsViewModel,
                currentResumeRevision: currentResumeRevision,
                force: true
            )
        }
    }

    func refresh(
        application: JobApplication,
        modelContext: ModelContext,
        settingsViewModel: SettingsViewModel,
        currentResumeRevision: ResumeMasterRevision? = nil,
        force: Bool
    ) async {
        guard !processingApplicationIDs.contains(application.id) else { return }
        processingApplicationIDs.insert(application.id)
        defer { processingApplicationIDs.remove(application.id) }

        let currentResumeRevision = currentResumeRevision ?? (try? ResumeStoreService.currentMasterRevision(in: modelContext))
        let preferences = settingsViewModel.jobMatchPreferences
        let existingAssessment = application.matchAssessment
        let descriptionHash = JobMatchScoringService.jobDescriptionHash(for: application)

        if !force,
           let existingAssessment,
           existingAssessment.status == .ready,
           !JobMatchScoringService.isStale(
            existingAssessment,
            application: application,
            currentResumeRevisionID: currentResumeRevision?.id,
            preferences: preferences
           ) {
            return
        }

        guard let currentResumeRevision else {
            let draft = JobMatchScoringService.blockedDraft(
                reason: .missingMasterResume,
                application: application,
                preferences: preferences
            )
            try? persist(
                draft: draft,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: nil,
                modelContext: modelContext
            )
            return
        }

        guard descriptionHash != nil else {
            let draft = JobMatchScoringService.blockedDraft(
                reason: .missingJobDescription,
                application: application,
                preferences: preferences
            )
            try? persist(
                draft: draft,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                modelContext: modelContext
            )
            return
        }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else {
            try? persistFailure(
                message: "No AI model configured. Check Settings.",
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                preferences: preferences,
                modelContext: modelContext
            )
            return
        }

        let requestStartedAt = Date()

        do {
            let draft = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await JobMatchScoringService.score(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    application: application,
                    resumeJSON: currentResumeRevision.rawJSON,
                    preferences: preferences
                )
            }
            try persist(
                draft: draft,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                modelContext: modelContext
            )
            _ = try? AIUsageLedgerService.record(
                feature: .jobMatchScoring,
                provider: provider,
                model: model,
                usage: draft.usage,
                status: .succeeded,
                applicationID: application.id,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: nil,
                in: modelContext
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            try? persistFailure(
                message: keyError.localizedDescription,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                preferences: preferences,
                modelContext: modelContext
            )
            _ = try? AIUsageLedgerService.record(
                feature: .jobMatchScoring,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                applicationID: application.id,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: keyError.localizedDescription,
                in: modelContext
            )
        } catch let aiError as AIServiceError {
            try? persistFailure(
                message: aiError.localizedDescription,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                preferences: preferences,
                modelContext: modelContext
            )
            _ = try? AIUsageLedgerService.record(
                feature: .jobMatchScoring,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                applicationID: application.id,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: aiError.localizedDescription,
                in: modelContext
            )
        } catch {
            try? persistFailure(
                message: error.localizedDescription,
                application: application,
                assessment: existingAssessment,
                resumeRevisionID: currentResumeRevision.id,
                preferences: preferences,
                modelContext: modelContext
            )
            _ = try? AIUsageLedgerService.record(
                feature: .jobMatchScoring,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                applicationID: application.id,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: error.localizedDescription,
                in: modelContext
            )
        }
    }

    private func persist(
        draft: JobMatchAssessmentDraft,
        application: JobApplication,
        assessment: JobMatchAssessment?,
        resumeRevisionID: UUID?,
        modelContext: ModelContext
    ) throws {
        let target = assessment ?? JobMatchAssessment()
        if assessment == nil {
            modelContext.insert(target)
            application.assignMatchAssessment(target)
            target.application = application
        }

        switch draft.status {
        case .ready:
            target.applyReadyState(
                overallScore: draft.overallScore,
                skillsScore: draft.skillsScore,
                experienceScore: draft.experienceScore,
                salaryScore: draft.salaryScore,
                locationScore: draft.locationScore,
                matchedSkills: draft.matchedSkills,
                missingSkills: draft.missingSkills,
                summary: draft.summary,
                gapAnalysis: draft.gapAnalysis,
                resumeRevisionID: resumeRevisionID,
                jobDescriptionHash: draft.jobDescriptionHash,
                preferencesFingerprint: draft.preferencesFingerprint,
                scoringVersion: draft.scoringVersion,
                scoredAt: draft.scoredAt,
                lastErrorMessage: nil
            )
        case .blocked:
            target.applyBlockedState(
                reason: draft.blockedReason ?? .missingPreferences,
                resumeRevisionID: resumeRevisionID,
                jobDescriptionHash: draft.jobDescriptionHash,
                preferencesFingerprint: draft.preferencesFingerprint,
                scoringVersion: draft.scoringVersion,
                message: draft.lastErrorMessage
            )
        case .failed:
            target.applyFailedState(
                resumeRevisionID: resumeRevisionID,
                jobDescriptionHash: draft.jobDescriptionHash,
                preferencesFingerprint: draft.preferencesFingerprint,
                scoringVersion: draft.scoringVersion,
                errorMessage: draft.lastErrorMessage ?? "Unknown job match scoring failure."
            )
        }

        try modelContext.save()
    }

    private func persistFailure(
        message: String,
        application: JobApplication,
        assessment: JobMatchAssessment?,
        resumeRevisionID: UUID?,
        preferences: JobMatchPreferences,
        modelContext: ModelContext
    ) throws {
        let target = assessment ?? JobMatchAssessment()
        if assessment == nil {
            modelContext.insert(target)
            application.assignMatchAssessment(target)
            target.application = application
        }

        target.applyFailedState(
            resumeRevisionID: resumeRevisionID,
            jobDescriptionHash: JobMatchScoringService.jobDescriptionHash(for: application),
            preferencesFingerprint: preferences.fingerprint,
            scoringVersion: JobMatchScoringService.scoringVersion,
            errorMessage: message
        )

        try modelContext.save()
    }
}
