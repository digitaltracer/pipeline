import Foundation
import SafariServices
import SwiftData
import PipelineKit
import os.log

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private static let logger = Logger(
        subsystem: Constants.App.bundleID + ".safari-extension",
        category: "ExtensionHandler"
    )

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem

        guard let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any],
              let command = message["command"] as? String else {
            respond(with: ["error": "Invalid request"], context: context)
            return
        }

        Task {
            let response: [String: Any]

            switch command {
            case "parse":
                response = await handleParse(message: message)
            case "check-duplicate":
                response = await handleDuplicateCheck(message: message)
            default:
                response = ["error": "Unknown command: \(command)"]
            }

            await MainActor.run {
                self.respond(with: response, context: context)
            }
        }
    }

    // MARK: - Parse Command

    private func handleParse(message: [String: Any]) async -> [String: Any] {
        let url = message["url"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let company = message["company"] as? String ?? ""
        let location = message["location"] as? String ?? ""
        let description = message["description"] as? String ?? ""
        let platform = message["platform"] as? String ?? "other"

        // Get AI settings
        let providerRaw = UserDefaults.standard.string(forKey: "selectedAIProvider") ?? "anthropic"
        guard let provider = AIProvider.allCases.first(where: { $0.rawValue.lowercased() == providerRaw.lowercased() }) else {
            return ["success": false, "error": "No AI provider configured"]
        }

        let apiKey: String
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
        } catch {
            return ["success": false, "error": "Could not access API key"]
        }

        guard !apiKey.isEmpty else {
            return ["success": false, "error": "API key not configured"]
        }

        let modelKey = "selectedAIModel_\(provider.rawValue)"
        let model = UserDefaults.standard.string(forKey: modelKey) ?? provider.defaultModels.first ?? ""

        // Check for duplicates first
        do {
            let container = try SharedContainer.makeModelContainer()
            let context = ModelContext(container)

            let dupResult = await MainActor.run {
                DuplicateDetectionService.checkForDuplicate(
                    url: url,
                    company: company,
                    role: title,
                    context: context
                )
            }

            if dupResult.isDuplicate {
                return [
                    "success": false,
                    "isDuplicate": true,
                    "error": "This job may already be saved: \(dupResult.matchReason ?? "duplicate detected")"
                ]
            }

            // Create the application directly from extracted data
            let application = JobApplication(
                companyName: company.isEmpty ? "Unknown Company" : company,
                role: title.isEmpty ? "Unknown Role" : title,
                location: location,
                jobURL: url.isEmpty ? nil : url,
                jobDescription: description.isEmpty ? nil : description,
                status: .saved,
                platform: Platform(rawValue: platform) ?? .other
            )

            await MainActor.run {
                context.insert(application)
                try? context.save()
            }

            Self.logger.info("Saved application: \(company) — \(title)")
            return ["success": true, "company": application.companyName, "role": application.role]

        } catch {
            Self.logger.error("Failed to save: \(error.localizedDescription)")
            return ["success": false, "error": error.localizedDescription]
        }
    }

    // MARK: - Duplicate Check Command

    private func handleDuplicateCheck(message: [String: Any]) async -> [String: Any] {
        let url = message["url"] as? String
        let company = message["company"] as? String
        let role = message["role"] as? String

        do {
            let container = try SharedContainer.makeModelContainer()
            let context = ModelContext(container)

            let result = await MainActor.run {
                DuplicateDetectionService.checkForDuplicate(
                    url: url,
                    company: company,
                    role: role,
                    context: context
                )
            }

            return [
                "isDuplicate": result.isDuplicate,
                "matchReason": result.matchReason ?? ""
            ]
        } catch {
            return ["isDuplicate": false, "error": error.localizedDescription]
        }
    }

    // MARK: - Response

    private func respond(with message: [String: Any], context: NSExtensionContext) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: message]
        context.completeRequest(returningItems: [response])
    }
}
