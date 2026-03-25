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
        let contact = BrowserCapturedContact(
            dictionary: message["contact"] as? [String: Any],
            fallbackCompanyName: company
        )
        let platform = message["platform"] as? String ?? ""
        let saveForLater = message["saveForLater"] as? Bool ?? false
        let postedAt = JobCaptureDateParser.parse(message["postedAt"] as? String)
        let applicationDeadline = JobCaptureDateParser.parse(message["applicationDeadline"] as? String)

        // Check for duplicates first
        do {
            let dupResult = try await duplicateCheck(
                url: url,
                company: company,
                role: title
            )

            if dupResult.isDuplicate {
                return [
                    "success": false,
                    "isDuplicate": true,
                    "error": "This job may already be saved: \(dupResult.matchReason ?? "duplicate detected")"
                ]
            }

            // Create the application directly from extracted data
            let application = try await saveParsedApplication(
                url: url,
                title: title,
                company: company,
                location: location,
                description: description,
                contact: contact,
                platform: platform,
                saveForLater: saveForLater,
                postedAt: postedAt,
                applicationDeadline: applicationDeadline
            )

            Self.logger.info("Saved application: \(company) — \(title), queued: \(saveForLater)")
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
            let result = try await duplicateCheck(
                url: url,
                company: company,
                role: role
            )

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

    @MainActor
    private func duplicateCheck(
        url: String?,
        company: String?,
        role: String?
    ) throws -> DuplicateDetectionService.DuplicateCheckResult {
        let container = try SharedContainer.makeModelContainer()
        let context = ModelContext(container)
        return DuplicateDetectionService.checkForDuplicate(
            url: url,
            company: company,
            role: role,
            context: context
        )
    }

    @MainActor
    private func saveParsedApplication(
        url: String,
        title: String,
        company: String,
        location: String,
        description: String,
        contact: BrowserCapturedContact?,
        platform: String,
        saveForLater: Bool,
        postedAt: Date?,
        applicationDeadline: Date?
    ) async throws -> JobApplication {
        let container = try SharedContainer.makeModelContainer()
        let context = ModelContext(container)

        let application = JobApplication(
            companyName: company.isEmpty ? "Unknown Company" : company,
            role: title.isEmpty ? "Unknown Role" : title,
            location: location,
            jobURL: url.isEmpty ? nil : url,
            jobDescription: description.isEmpty ? nil : description,
            status: .saved,
            platform: Platform.resolve(rawPlatform: platform, url: url),
            isInApplyQueue: saveForLater,
            queuedAt: saveForLater ? Date() : nil,
            postedAt: postedAt,
            applicationDeadline: applicationDeadline
        )

        context.insert(application)
        _ = try? CompanyLinkingService.ensureCompanyLinked(for: application, in: context)
        do {
            try BrowserCaptureContactService.attach(contact, to: application, in: context)
        } catch {
            Self.logger.error("Failed to attach captured contact: \(error.localizedDescription)")
        }
        try? ApplicationChecklistService().sync(for: application, trigger: .applicationCreated, in: context)
        ApplicationTimelineRecorderService.seedInitialHistory(for: application, in: context)

        // Ensure the application is durably saved even if checklist sync skipped the save.
        if context.hasChanges {
            try context.save()
        }

        await syncApplyQueueReminderIfNeeded(afterSavingQueuedApplication: saveForLater, context: context)
        return application
    }

    @MainActor
    private func syncApplyQueueReminderIfNeeded(
        afterSavingQueuedApplication saveForLater: Bool,
        context: ModelContext
    ) async {
        guard saveForLater,
              let sharedDefaults = UserDefaults(suiteName: SharedContainer.appGroupID) else {
            return
        }

        let notificationsEnabled = sharedDefaults.bool(forKey: Constants.UserDefaultsKeys.notificationsEnabled)
        let storedDailyTarget = sharedDefaults.integer(forKey: Constants.UserDefaultsKeys.applyQueueDailyTarget)
        let dailyTarget = (1...12).contains(storedDailyTarget) ? storedDailyTarget : ApplyQueueService.defaultDailyTarget
        let storedHour = sharedDefaults.integer(forKey: Constants.UserDefaultsKeys.applyQueueNotificationHour)
        let hour = (0...23).contains(storedHour) ? storedHour : 9
        let storedMinute = sharedDefaults.integer(forKey: Constants.UserDefaultsKeys.applyQueueNotificationMinute)
        let minute = (0...59).contains(storedMinute) ? storedMinute : 0

        let applications = (try? context.fetch(FetchDescriptor<JobApplication>())) ?? []
        let currentResumeRevisionID = try? ResumeStoreService.currentMasterRevision(in: context)?.id

        await NotificationService.shared.syncApplyQueueReminder(
            applications: applications,
            notificationsEnabled: notificationsEnabled,
            dailyTarget: dailyTarget,
            hour: hour,
            minute: minute,
            currentResumeRevisionID: currentResumeRevisionID,
            matchPreferences: JobMatchPreferences()
        )
    }
}
