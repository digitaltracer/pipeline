import Foundation
import Observation
import SwiftData
import PipelineKit

@MainActor
@Observable
final class JobDescriptionDenoiseViewModel {
    var isLoading = false
    var error: String?
    var originalDescription: String?
    var cleanedDescription: String?
    var isShowingReview = false

    private let application: JobApplication
    private let settingsViewModel: SettingsViewModel
    private var modelContext: ModelContext?

    init(
        application: JobApplication,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext? = nil
    ) {
        self.application = application
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
    }

    func setModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func clearError() {
        error = nil
    }

    func generateProposal() async {
        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else {
            error = "No job description available to denoise."
            return
        }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await JobDescriptionDenoiseService.denoiseDescription(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    description: description
                )
            }

            originalDescription = description
            cleanedDescription = result.cleanedDescription
            isShowingReview = true
            recordUsage(
                feature: .jobDescriptionDenoise,
                provider: provider,
                model: model,
                usage: result.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .jobDescriptionDenoise,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordUsage(
                feature: .jobDescriptionDenoise,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            self.error = "Failed to denoise job description: \(error.localizedDescription)"
            recordUsage(
                feature: .jobDescriptionDenoise,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
        }
    }

    func dismissReview() {
        isShowingReview = false
        originalDescription = nil
        cleanedDescription = nil
    }

    func applyReplacement() {
        guard let modelContext else {
            error = "Could not save the cleaned job description."
            return
        }

        guard let cleanedDescription else {
            error = "No cleaned job description is available."
            return
        }

        let trimmed = cleanedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        application.jobDescription = trimmed.isEmpty ? nil : trimmed
        application.updateTimestamp()

        do {
            try modelContext.save()
            dismissReview()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func recordUsage(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: feature,
            provider: provider,
            model: model,
            usage: usage,
            status: status,
            applicationID: application.id,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }
}
