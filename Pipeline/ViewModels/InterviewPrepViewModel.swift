import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class InterviewPrepViewModel {
    var isLoading = false
    var error: String?
    var result: InterviewPrepResult?

    private let application: JobApplication
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext?

    init(
        application: JobApplication,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext? = nil
    ) {
        self.application = application
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
    }

    var hasResult: Bool { result != nil }

    @MainActor
    func generate() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return
        }

        let keys: [String]
        do {
            keys = try settingsViewModel.apiKeys(for: provider)
        } catch {
            self.error = "Could not access API key. Please check Settings."
            return
        }

        guard !keys.isEmpty else {
            error = "API key not configured for \(provider.rawValue). Please check Settings."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        result = nil
        defer { isLoading = false }

        // Gather interview stage from latest interview log
        let interviewStage: String
        if let latestLog = application.interviewLogs?
            .sorted(by: { $0.date > $1.date })
            .first {
            interviewStage = latestLog.interviewType.displayName
        } else {
            interviewStage = ""
        }

        // Gather notes from interview logs
        let notes = (application.interviewLogs ?? [])
            .sorted { $0.date > $1.date }
            .compactMap { log -> String? in
                guard let n = log.notes, !n.isEmpty else { return nil }
                return n
            }
            .joined(separator: "\n")

        do {
            let prepResult = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await InterviewPrepService.generatePrep(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    role: application.role,
                    company: application.companyName,
                    jobDescription: application.jobDescription ?? "",
                    interviewStage: interviewStage,
                    notes: notes
                )
            }
            result = prepResult
            recordUsage(
                feature: .interviewPrep,
                provider: provider,
                model: model,
                usage: prepResult.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .interviewPrep,
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
                feature: .interviewPrep,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            self.error = "Failed to generate interview prep: \(error.localizedDescription)"
            recordUsage(
                feature: .interviewPrep,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
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
