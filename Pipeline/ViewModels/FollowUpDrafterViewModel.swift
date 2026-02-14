import Foundation
import SwiftUI
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

    init(application: JobApplication, settingsViewModel: SettingsViewModel) {
        self.application = application
        self.settingsViewModel = settingsViewModel
    }

    var hasResult: Bool { result != nil }

    var daysSinceLastContact: Int {
        let referenceDate: Date
        if let latestLog = application.interviewLogs?
            .sorted(by: { $0.date > $1.date })
            .first {
            referenceDate = latestLog.date
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

        let apiKey: String
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
        } catch {
            self.error = "Could not access API key. Please check Settings."
            return
        }

        guard !apiKey.isEmpty else {
            error = "API key not configured for \(provider.rawValue). Please check Settings."
            return
        }

        isLoading = true
        error = nil
        result = nil
        defer { isLoading = false }

        // Gather current stage
        let stage: String
        if let latestLog = application.interviewLogs?
            .sorted(by: { $0.date > $1.date })
            .first {
            stage = latestLog.interviewType.displayName
        } else {
            stage = application.status.displayName
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
            let emailResult = try await FollowUpDrafterService.generateFollowUp(
                provider: provider,
                apiKey: apiKey,
                model: model,
                company: application.companyName,
                role: application.role,
                stage: stage,
                notes: notes,
                daysSinceLastContact: daysSinceLastContact
            )
            result = emailResult
            editableSubject = emailResult.subject
            editableBody = emailResult.body
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
        } catch {
            self.error = "Failed to generate follow-up email: \(error.localizedDescription)"
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
        components.path = ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: editableSubject),
            URLQueryItem(name: "body", value: editableBody)
        ]
        return components.url
    }
}
