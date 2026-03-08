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

    private func resolvePlatform(rawPlatform: String?, url: String) -> Platform {
        let detected = Platform.detect(from: url)
        if detected != .other { return detected }

        let normalized = (rawPlatform ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "linkedin", "linkedin.com", "linkedin jobs":
            return .linkedin
        case "indeed", "indeed.com":
            return .indeed
        case "glassdoor", "glassdoor.com":
            return .glassdoor
        case "naukri", "naukri.com":
            return .naukri
        case "instahyre", "instahyre.com":
            return .instahyre
        default:
            return .other
        }
    }

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
        let platform = message["platform"] as? String ?? ""

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
                platform: resolvePlatform(rawPlatform: platform, url: url)
            )

            await MainActor.run {
                context.insert(application)
                try? ApplicationChecklistService().sync(for: application, trigger: .applicationCreated, in: context)
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
