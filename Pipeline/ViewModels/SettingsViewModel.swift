import Foundation
import SwiftUI

@Observable
final class SettingsViewModel {
    // MARK: - Appearance

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
        }
    }

    // MARK: - AI Provider

    var selectedAIProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedAIProvider.rawValue, forKey: "selectedAIProvider")
        }
    }

    var selectedAIModel: String {
        didSet {
            UserDefaults.standard.set(selectedAIModel, forKey: "selectedAIModel")
        }
    }

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled")
        }
    }

    var reminderTiming: ReminderTiming {
        didSet {
            UserDefaults.standard.set(reminderTiming.rawValue, forKey: "reminderTiming")
        }
    }

    // MARK: - Initialization

    init() {
        // Load appearance
        if let rawValue = UserDefaults.standard.string(forKey: "appearanceMode"),
           let mode = AppearanceMode(rawValue: rawValue) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        // Load AI provider
        if let rawValue = UserDefaults.standard.string(forKey: "selectedAIProvider"),
           let provider = AIProvider(rawValue: rawValue) {
            self.selectedAIProvider = provider
        } else {
            self.selectedAIProvider = .openAI
        }

        self.selectedAIModel = UserDefaults.standard.string(forKey: "selectedAIModel") ?? AIProvider.openAI.models.first ?? ""

        // Load notifications
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")

        if let rawValue = UserDefaults.standard.string(forKey: "reminderTiming"),
           let timing = ReminderTiming(rawValue: rawValue) {
            self.reminderTiming = timing
        } else {
            self.reminderTiming = .dayBefore
        }
    }

    // MARK: - Methods

    func getColorScheme() -> ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }
}

// MARK: - Enums

enum AppearanceMode: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        case .system: return "circle.lefthalf.filled"
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Google Gemini"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .openAI: return "brain"
        case .anthropic: return "sparkles"
        case .gemini: return "wand.and.stars"
        }
    }

    var models: [String] {
        switch self {
        case .openAI:
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .anthropic:
            return ["claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case .gemini:
            return ["gemini-1.5-pro", "gemini-1.5-flash", "gemini-pro"]
        }
    }

    var keychainKey: String {
        switch self {
        case .openAI: return "com.pipeline.openai-api-key"
        case .anthropic: return "com.pipeline.anthropic-api-key"
        case .gemini: return "com.pipeline.gemini-api-key"
        }
    }
}

enum ReminderTiming: String, CaseIterable, Identifiable {
    case dayBefore = "Day Before"
    case morningOf = "Morning Of (9 AM)"
    case both = "Both"

    var id: String { rawValue }
}
