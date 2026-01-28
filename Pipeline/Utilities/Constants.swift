import Foundation
import SwiftUI

enum Constants {
    // MARK: - App Info

    enum App {
        static let name = "Pipeline"
        static let bundleID = "com.pipeline.app"
        static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    // MARK: - iCloud

    enum iCloud {
        static let containerID = "iCloud.com.pipeline.app"
    }

    // MARK: - UI Constants

    enum UI {
        // Card dimensions
        static let cardMinWidth: CGFloat = 280
        static let cardMaxWidth: CGFloat = 350
        static let cardSpacing: CGFloat = 16

        // Avatar sizes
        static let avatarSmall: CGFloat = 32
        static let avatarMedium: CGFloat = 48
        static let avatarLarge: CGFloat = 64

        // Corner radii
        static let cornerRadiusSmall: CGFloat = 4
        static let cornerRadiusMedium: CGFloat = 8
        static let cornerRadiusLarge: CGFloat = 12

        // Padding
        static let paddingSmall: CGFloat = 4
        static let paddingMedium: CGFloat = 8
        static let paddingLarge: CGFloat = 16

        // Animation durations
        static let animationFast: Double = 0.15
        static let animationNormal: Double = 0.25
        static let animationSlow: Double = 0.4
    }

    // MARK: - Sidebar

    enum Sidebar {
        static let minWidth: CGFloat = 200
        static let idealWidth: CGFloat = 220
        static let maxWidth: CGFloat = 280
    }

    // MARK: - Content Column

    enum Content {
        static let minWidth: CGFloat = 400
        static let idealWidth: CGFloat = 500
        static let maxWidth: CGFloat = 700
    }

    // MARK: - External URLs

    enum URLs {
        static let clearbitLogo = "https://logo.clearbit.com/"
        static let privacyPolicy = "https://github.com"
        static let termsOfService = "https://github.com"
        static let support = "https://github.com"

        // API Documentation
        static let openAIDocs = "https://platform.openai.com/docs"
        static let anthropicDocs = "https://docs.anthropic.com"
        static let geminiDocs = "https://ai.google.dev/docs"

        // API Key Pages
        static let openAIKeys = "https://platform.openai.com/api-keys"
        static let anthropicConsole = "https://console.anthropic.com/"
        static let geminiKeys = "https://makersuite.google.com/app/apikey"
    }

    // MARK: - UserDefaults Keys

    enum UserDefaultsKeys {
        static let appearanceMode = "appearanceMode"
        static let selectedAIProvider = "selectedAIProvider"
        static let selectedAIModel = "selectedAIModel"
        static let notificationsEnabled = "notificationsEnabled"
        static let reminderTiming = "reminderTiming"
        static let lastSyncDate = "lastSyncDate"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    // MARK: - Notification Identifiers

    enum Notifications {
        static let followUpReminderCategory = "FOLLOWUP_REMINDER"
        static let followUpIdentifierPrefix = "followup-"
    }

    // MARK: - Limits

    enum Limits {
        static let maxJobDescriptionLength = 50000
        static let maxNotesLength = 10000
        static let maxURLLength = 2048
        static let webContentMaxLength = 15000 // For AI parsing
    }
}

// MARK: - Color Extensions

extension Color {
    static let pipelineBlue = Color(red: 0.2, green: 0.4, blue: 0.9)
    static let pipelineGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let pipelineOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let pipelineRed = Color(red: 0.9, green: 0.3, blue: 0.3)
}
