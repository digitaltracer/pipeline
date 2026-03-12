import Foundation
import Observation
import SwiftData
import PipelineKit

@MainActor
@Observable
final class ChecklistSuggestionsViewModel {
    var isLoading = false
    var error: String?

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

    var pendingSuggestions: [ApplicationChecklistSuggestion] {
        application.pendingChecklistSuggestions
    }

    var hasGeneratedSuggestions: Bool {
        !(application.checklistSuggestions ?? []).isEmpty
    }

    func setModelContext(_ modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func clearError() {
        error = nil
    }

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

        guard let modelContext else {
            error = "Pipeline could not load suggestions for this application."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await ChecklistSuggestionService.generateSuggestions(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    application: application
                )
            }

            let filteredSuggestions = filterCandidates(result.suggestions)
            try replacePendingSuggestions(with: filteredSuggestions, in: modelContext)
            recordUsage(
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
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            self.error = "Failed to generate checklist suggestions: \(error.localizedDescription)"
            recordUsage(
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
        }
    }

    func accept(_ suggestion: ApplicationChecklistSuggestion) {
        guard let modelContext else {
            error = "Pipeline could not save this task."
            return
        }

        let normalizedTitle = suggestion.displayTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            error = "Suggestion title was empty."
            return
        }

        let existingTaskTitles = Set(application.sortedTasks.map { normalize($0.displayTitle) })
        let normalizedSuggestionTitle = normalize(normalizedTitle)

        if !existingTaskTitles.contains(normalizedSuggestionTitle) {
            let task = ApplicationTask(
                title: normalizedTitle,
                notes: suggestion.normalizedRationale,
                priority: .medium,
                application: application,
                origin: .manual
            )
            modelContext.insert(task)
            application.addTask(task)
        }

        suggestion.status = .accepted
        suggestion.updateTimestamp()
        application.updateTimestamp()

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

    func dismiss(_ suggestion: ApplicationChecklistSuggestion) {
        guard let modelContext else {
            error = "Pipeline could not update this suggestion."
            return
        }

        suggestion.status = .dismissed
        suggestion.updateTimestamp()
        application.updateTimestamp()

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            self.error = error.localizedDescription
        }
    }

    private func replacePendingSuggestions(
        with candidates: [ChecklistSuggestionCandidate],
        in modelContext: ModelContext
    ) throws {
        let pendingSuggestions = application.pendingChecklistSuggestions
        for suggestion in pendingSuggestions {
            modelContext.delete(suggestion)
        }
        application.checklistSuggestions?.removeAll(where: { $0.status == .pending })

        for candidate in candidates {
            let suggestion = ApplicationChecklistSuggestion(
                title: candidate.title,
                rationale: candidate.rationale,
                status: .pending,
                application: application
            )
            modelContext.insert(suggestion)
            application.addChecklistSuggestion(suggestion)
        }

        application.updateTimestamp()
        try modelContext.save()
    }

    private func filterCandidates(_ candidates: [ChecklistSuggestionCandidate]) -> [ChecklistSuggestionCandidate] {
        let taskTitles = Set(application.sortedTasks.map { normalize($0.displayTitle) })
        let preservedSuggestionTitles = Set(
            application.sortedChecklistSuggestions
                .filter { $0.status != .pending }
                .map { normalize($0.displayTitle) }
        )

        var seen = Set<String>()

        return candidates.filter { candidate in
            let normalizedTitle = normalize(candidate.title)
            guard !normalizedTitle.isEmpty else { return false }
            guard !taskTitles.contains(normalizedTitle) else { return false }
            guard !preservedSuggestionTitles.contains(normalizedTitle) else { return false }
            return seen.insert(normalizedTitle).inserted
        }
    }

    private func recordUsage(
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: .checklistSuggestions,
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

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
