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

    // MARK: - Browser Extensions

    public enum BrowserExtensions {
        public enum Chrome {
            public static let extensionID = "onkppiodpcchcgjcfkpdbaiadjdcaejf"
            public static let nativeHostName = "io.github.digitaltracer.pipeline"
            public static let nativeHostExecutableName = "PipelineNativeHost"
        }
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
        public static let darkThemeStyle = "darkThemeStyle"
        public static let lightThemeStyle = "lightThemeStyle"
        public static let selectedAIProvider = "selectedAIProvider"
        public static let selectedAIModel = "selectedAIModel"
        public static let customModelsByProviderID = "customModelsByProviderID"
        public static let cloudSyncEnabled = "cloudSyncEnabled"
        public static let cloudSyncStartupError = "cloudSyncStartupError"
        public static let appLockEnabled = "appLockEnabled"
        public static let notificationsEnabled = "notificationsEnabled"
        public static let reminderTiming = "reminderTiming"
        public static let weeklyDigestNotificationsEnabled = "weeklyDigestNotificationsEnabled"
        public static let weeklyDigestWeekday = "weeklyDigestWeekday"
        public static let weeklyDigestHour = "weeklyDigestHour"
        public static let weeklyDigestMinute = "weeklyDigestMinute"
        public static let applyQueueDailyTarget = "applyQueueDailyTarget"
        public static let applyQueueNotificationHour = "applyQueueNotificationHour"
        public static let applyQueueNotificationMinute = "applyQueueNotificationMinute"
        public static let analyticsBaseCurrency = "analyticsBaseCurrency"
        public static let jobMatchPreferredCurrency = "jobMatchPreferredCurrency"
        public static let jobMatchPreferredSalaryMinText = "jobMatchPreferredSalaryMinText"
        public static let jobMatchPreferredSalaryMaxText = "jobMatchPreferredSalaryMaxText"
        public static let jobMatchAllowedWorkModes = "jobMatchAllowedWorkModes"
        public static let jobMatchPreferredLocations = "jobMatchPreferredLocations"
        public static let hiddenStatusesInAllApplications = "hiddenStatusesInAllApplications"
        public static let customApplicationStatuses = "customApplicationStatuses"
        public static let customSources = "customSources"
        public static let customInterviewStages = "customInterviewStages"
        public static let lastSyncDate = "lastSyncDate"
        public static let hasCompletedOnboarding = "hasCompletedOnboarding"
        public static let onboardingGuidanceMuted = "onboardingGuidanceMuted"
        public static let onboardingLastSeenVersion = "onboardingLastSeenVersion"
    }

    // MARK: - Settings Sync

    public enum Sync {
        /// UserDefaults keys that should sync to iCloud via NSUbiquitousKeyValueStore.
        /// Anything not in this set stays local (caches, device-specific toggles, sync-control itself).
        public static let syncableUserDefaultsKeys: Set<String> = [
            UserDefaultsKeys.appearanceMode,
            UserDefaultsKeys.darkThemeStyle,
            UserDefaultsKeys.lightThemeStyle,
            UserDefaultsKeys.selectedAIProvider,
            UserDefaultsKeys.selectedAIModel,
            UserDefaultsKeys.customModelsByProviderID,
            UserDefaultsKeys.notificationsEnabled,
            UserDefaultsKeys.reminderTiming,
            UserDefaultsKeys.weeklyDigestNotificationsEnabled,
            UserDefaultsKeys.weeklyDigestWeekday,
            UserDefaultsKeys.weeklyDigestHour,
            UserDefaultsKeys.weeklyDigestMinute,
            UserDefaultsKeys.applyQueueDailyTarget,
            UserDefaultsKeys.applyQueueNotificationHour,
            UserDefaultsKeys.applyQueueNotificationMinute,
            UserDefaultsKeys.analyticsBaseCurrency,
            UserDefaultsKeys.jobMatchPreferredCurrency,
            UserDefaultsKeys.jobMatchPreferredSalaryMinText,
            UserDefaultsKeys.jobMatchPreferredSalaryMaxText,
            UserDefaultsKeys.jobMatchAllowedWorkModes,
            UserDefaultsKeys.jobMatchPreferredLocations,
            UserDefaultsKeys.hiddenStatusesInAllApplications,
            UserDefaultsKeys.hasCompletedOnboarding,
            UserDefaultsKeys.onboardingGuidanceMuted,
            UserDefaultsKeys.onboardingLastSeenVersion,
            UserDefaultsKeys.customApplicationStatuses,
            UserDefaultsKeys.customSources,
            UserDefaultsKeys.customInterviewStages
        ]
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
