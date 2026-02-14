import Foundation
import SwiftData
import PipelineKit

enum NativeMessageHandler {

    // MARK: - Parse

    static func handleParse(message: [String: Any]) async -> [String: Any] {
        let url = message["url"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let company = message["company"] as? String ?? ""
        let location = message["location"] as? String ?? ""
        let description = message["description"] as? String ?? ""
        let platform = message["platform"] as? String ?? "other"

        do {
            let container = try SharedContainer.makeModelContainer()
            let context = ModelContext(container)

            // Check for duplicates
            let dupResult = await MainActor.run {
                DuplicateDetectionService.checkForDuplicate(
                    url: url.isEmpty ? nil : url,
                    company: company.isEmpty ? nil : company,
                    role: title.isEmpty ? nil : title,
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

            // Create the application
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

            return ["success": true, "company": application.companyName, "role": application.role]

        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }

    // MARK: - Duplicate Check

    static func handleDuplicateCheck(message: [String: Any]) async -> [String: Any] {
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
}
