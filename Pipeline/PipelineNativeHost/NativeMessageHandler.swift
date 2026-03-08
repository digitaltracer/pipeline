import Foundation
import SwiftData
import PipelineKit

enum NativeMessageHandler {

    private static func preflightStoreAccess() -> String? {
        let fm = FileManager.default
        let storeURL = SharedContainer.resolvedStoreURL()
        let storeDirectory = storeURL.deletingLastPathComponent()

        do {
            try fm.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        } catch {
            return "Unable to create store directory at \(storeDirectory.path): \(error.localizedDescription)"
        }

        guard fm.isWritableFile(atPath: storeDirectory.path) else {
            return "No write access to \(storeDirectory.path)"
        }

        if fm.fileExists(atPath: storeURL.path), !fm.isWritableFile(atPath: storeURL.path) {
            return "No write access to \(storeURL.path)"
        }

        return nil
    }

    private static func resolvePlatform(rawPlatform: String?, url: String) -> Platform {
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

    // MARK: - Parse

    static func handleParse(message: [String: Any]) async -> [String: Any] {
        let url = message["url"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let company = message["company"] as? String ?? ""
        let location = message["location"] as? String ?? ""
        let description = message["description"] as? String ?? ""
        let platform = message["platform"] as? String ?? "other"

        if let accessError = preflightStoreAccess() {
            return [
                "success": false,
                "error": "Pipeline data store is not writable. \(accessError). Check macOS privacy permissions and reinstall the native host."
            ]
        }

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
                platform: resolvePlatform(rawPlatform: platform, url: url)
            )

            await MainActor.run {
                context.insert(application)
                try? ApplicationChecklistService().sync(for: application, trigger: .applicationCreated, in: context)
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

        if let accessError = preflightStoreAccess() {
            return [
                "isDuplicate": false,
                "error": "Pipeline data store is not writable. \(accessError). Check macOS privacy permissions and reinstall the native host."
            ]
        }

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
