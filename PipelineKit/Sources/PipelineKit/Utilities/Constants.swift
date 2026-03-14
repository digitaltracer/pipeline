import Foundation

public enum Constants {
    // MARK: - App Info

    public enum App {
        public static let name = "Pipeline"
        public static let legacyBundleID = "com.pipeline.app"
        public static let bundleID: String = {
            let candidate = Bundle.main.bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let candidate, !candidate.isEmpty, !candidate.contains("xctest") else {
                return "io.github.digitaltracer.pipeline"
            }
            return candidate
        }()
        public static let version: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        public static let build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - iCloud

    public enum iCloud {
        public static let containerID = "iCloud.com.pipeline.app"
        public static let attachmentsDirectoryName = "Applications"
        public static let attachmentsSubdirectoryName = "Attachments"
        public static let localFallbackDocumentsDirectoryName = "Documents"
    }

    // MARK: - External URLs

    public enum URLs {
        public static let privacyPolicy = "https://github.com/digitaltracer/pipeline"
        public static let termsOfService = "https://github.com"
        public static let support = "https://github.com/digitaltracer/pipeline/issues"

        // API Documentation
        public static let openAIDocs = "https://platform.openai.com/docs"
        public static let anthropicDocs = "https://docs.anthropic.com"
        public static let geminiDocs = "https://ai.google.dev/docs"

        // API Key Pages
        public static let openAIKeys = "https://platform.openai.com/api-keys"
        public static let anthropicConsole = "https://console.anthropic.com/"
        public static let geminiKeys = "https://makersuite.google.com/app/apikey"
    }

    // MARK: - UserDefaults Keys

    public enum UserDefaultsKeys {
        public static let appearanceMode = "appearanceMode"
        public static let selectedAIProvider = "selectedAIProvider"
        public static let selectedAIModel = "selectedAIModel"
        public static let cloudSyncEnabled = "cloudSyncEnabled"
        public static let appLockEnabled = "appLockEnabled"
        public static let notificationsEnabled = "notificationsEnabled"
        public static let reminderTiming = "reminderTiming"
        public static let weeklyDigestNotificationsEnabled = "weeklyDigestNotificationsEnabled"
        public static let weeklyDigestWeekday = "weeklyDigestWeekday"
        public static let weeklyDigestHour = "weeklyDigestHour"
        public static let weeklyDigestMinute = "weeklyDigestMinute"
        public static let analyticsBaseCurrency = "analyticsBaseCurrency"
        public static let lastSyncDate = "lastSyncDate"
        public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Notification Identifiers

    public enum Notifications {
        public static let followUpReminderCategory = "FOLLOWUP_REMINDER"
        public static let followUpIdentifierPrefix = "followup-"
    }

    // MARK: - Limits

    public enum Limits {
        public static let maxJobDescriptionLength = 50000
        public static let maxNotesLength = 10000
        public static let maxURLLength = 2048
        public static let webContentMaxLength = 15000
    }
}
