import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class InterviewPrepViewModel {
    var isLoading = false
    var error: String?
    var result: InterviewPrepResult?
    var personalQuestionHighlights: [InterviewQuestionBankEntry] = []
    var personalHistorySignals: [String] = []

    private let application: JobApplication
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext?
    private let learningBuilder = InterviewLearningContextBuilder()

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

        let interviewStage: String
        if let latestInterview = application.sortedActivities
            .first(where: { $0.kind == .interview }) {
            interviewStage = latestInterview.interviewStage?.displayName ?? latestInterview.kind.displayName
        } else {
            interviewStage = ""
        }

        let notes = notesContext()
        let prepHistory = loadPersonalHistory()

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
                    notes: notes,
                    personalQuestionBankContext: prepHistory.questionContext,
                    learningSummary: prepHistory.learningSummary
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

    private func notesContext() -> String {
        var sections: [String] = []

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Overview Notes:\n\(overview)")
        }

        let activityNotes = application.sortedActivities
            .filter { !$0.isSystemGenerated }
            .compactMap { activity -> String? in
                switch activity.kind {
                case .email:
                    return activity.emailBodySnapshot ?? activity.notes
                default:
                    return activity.notes
                }
            }
            .joined(separator: "\n")

        if !activityNotes.isEmpty {
            sections.append("Activity Notes:\n\(activityNotes)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func loadPersonalHistory() -> (questionContext: String, learningSummary: String) {
        guard let modelContext else {
            personalQuestionHighlights = []
            personalHistorySignals = []
            return ("", "")
        }

        let applications = (try? modelContext.fetch(FetchDescriptor<JobApplication>())) ?? []
        let personalizedContext = learningBuilder.personalizedPrepContext(
            for: application,
            in: applications
        )
        personalQuestionHighlights = personalizedContext.boostedQuestions

        var snapshotDescriptor = FetchDescriptor<InterviewLearningSnapshot>(
            sortBy: [SortDescriptor(\InterviewLearningSnapshot.generatedAt, order: .reverse)]
        )
        snapshotDescriptor.fetchLimit = 1
        let latestSnapshot = (try? modelContext.fetch(snapshotDescriptor))?.first
        personalHistorySignals = Array(
            ((latestSnapshot?.strengths ?? []) + (latestSnapshot?.growthAreas ?? []))
                .prefix(6)
        )

        let questionContext = personalizedContext.boostedQuestions.map { entry in
            var line = "- [\(entry.category.displayName)] \(entry.question)"
            line += " (\(entry.companyName)"
            if let stage = entry.interviewStage {
                line += ", \(stage.displayName)"
            }
            line += ")"
            if let answerNotes = entry.answerNotes, !answerNotes.isEmpty {
                line += " :: \(answerNotes)"
            }
            return line
        }.joined(separator: "\n")

        return (
            questionContext,
            latestSnapshot.map { snapshot in
                ((snapshot.strengths + snapshot.growthAreas + snapshot.recommendedFocusAreas).prefix(8))
                    .joined(separator: "\n")
            } ?? personalizedContext.learningSummary
        )
    }
}
