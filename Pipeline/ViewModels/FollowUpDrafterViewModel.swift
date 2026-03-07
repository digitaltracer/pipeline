import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class FollowUpDrafterViewModel {
    var isLoading = false
    var error: String?
    var result: FollowUpEmailResult?

    // Editable fields — initialized from AI result, user can modify
    var editableSubject: String = ""
    var editableBody: String = ""

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

    var applicationForLogging: JobApplication { application }

    var daysSinceLastContact: Int {
        let referenceDate: Date
        if let latestActivity = application.sortedActivities
            .first {
            referenceDate = latestActivity.occurredAt
        } else {
            referenceDate = application.updatedAt
        }

        return Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
    }

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

        // Gather current stage
        let stage: String
        if let latestInterview = application.sortedActivities
            .first(where: { $0.kind == .interview }) {
            stage = latestInterview.interviewStage?.displayName ?? latestInterview.kind.displayName
        } else {
            stage = application.status.displayName
        }

        let notes = application.sortedActivities
            .compactMap { activity -> String? in
                switch activity.kind {
                case .email:
                    return activity.emailBodySnapshot ?? activity.notes
                default:
                    return activity.notes
                }
            }
            .joined(separator: "\n")

        do {
            let emailResult = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await FollowUpDrafterService.generateFollowUp(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    company: application.companyName,
                    role: application.role,
                    stage: stage,
                    notes: notes,
                    daysSinceLastContact: daysSinceLastContact
                )
            }
            result = emailResult
            editableSubject = emailResult.subject
            editableBody = emailResult.body
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: emailResult.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .followUpDraft,
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
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            self.error = "Failed to generate follow-up email: \(error.localizedDescription)"
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
        }
    }

    func copyToClipboard() {
        let text = "Subject: \(editableSubject)\n\n\(editableBody)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = application.primaryContactLink?.contact?.email ?? ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: editableSubject),
            URLQueryItem(name: "body", value: editableBody)
        ]
        return components.url
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
