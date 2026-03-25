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

    // MARK: - Parse

    static func handleParse(message: [String: Any]) async -> [String: Any] {
        let url = message["url"] as? String ?? ""
        let title = message["title"] as? String ?? ""
        let company = message["company"] as? String ?? ""
        let location = message["location"] as? String ?? ""
        let description = message["description"] as? String ?? ""
        let contact = BrowserCapturedContact(
            dictionary: message["contact"] as? [String: Any],
            fallbackCompanyName: company
        )
        let platform = message["platform"] as? String ?? "other"
        let saveForLater = message["saveForLater"] as? Bool ?? false
        let postedAt = JobCaptureDateParser.parse(message["postedAt"] as? String)
        let applicationDeadline = JobCaptureDateParser.parse(message["applicationDeadline"] as? String)

        if let accessError = preflightStoreAccess() {
            return [
                "success": false,
                "error": "Pipeline data store is not writable. \(accessError). Check macOS privacy permissions and reinstall the native host."
            ]
        }

        do {
            let dupResult = try await duplicateCheck(
                url: url.isEmpty ? nil : url,
                company: company.isEmpty ? nil : company,
                role: title.isEmpty ? nil : title
            )

            if dupResult.isDuplicate {
                return [
                    "success": false,
                    "isDuplicate": true,
                    "error": "This job may already be saved: \(dupResult.matchReason ?? "duplicate detected")"
                ]
            }

            // Create the application
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

    @MainActor
    private static func duplicateCheck(
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
    private static func saveParsedApplication(
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
        _ = try? BrowserCaptureContactService.attach(contact, to: application, in: context)
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
    private static func syncApplyQueueReminderIfNeeded(
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
