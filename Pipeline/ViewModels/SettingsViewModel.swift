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
            ensureSelectedAIModelIsValid()
        }
    }

    var selectedAIModel: String {
        didSet {
            UserDefaults.standard.set(selectedAIModel, forKey: "selectedAIModel")
        }
    }

    // MARK: - Custom Models

    var customOpenAIModels: [String] {
        didSet {
            UserDefaults.standard.set(customOpenAIModels, forKey: "customOpenAIModels")
        }
    }

    var customAnthropicModels: [String] {
        didSet {
            UserDefaults.standard.set(customAnthropicModels, forKey: "customAnthropicModels")
        }
    }

    var customGeminiModels: [String] {
        didSet {
            UserDefaults.standard.set(customGeminiModels, forKey: "customGeminiModels")
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

        self.selectedAIModel = UserDefaults.standard.string(forKey: "selectedAIModel") ?? ""

        self.customOpenAIModels = UserDefaults.standard.stringArray(forKey: "customOpenAIModels") ?? []
        self.customAnthropicModels = UserDefaults.standard.stringArray(forKey: "customAnthropicModels") ?? []
        self.customGeminiModels = UserDefaults.standard.stringArray(forKey: "customGeminiModels") ?? []

        // Load notifications
        self.notificationsEnabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")

        if let rawValue = UserDefaults.standard.string(forKey: "reminderTiming"),
           let timing = ReminderTiming(rawValue: rawValue) {
            self.reminderTiming = timing
        } else {
            self.reminderTiming = .dayBefore
        }

        migrateSelectedAIModelIfNeeded()
        ensureSelectedAIModelIsValid()
    }

    // MARK: - Methods

    func getColorScheme() -> ColorScheme? {
        switch appearanceMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    func availableModels(for provider: AIProvider) -> [String] {
        let customModels: [String]
        switch provider {
        case .openAI:
            customModels = customOpenAIModels
        case .anthropic:
            customModels = customAnthropicModels
        case .gemini:
            customModels = customGeminiModels
        }

        let base = provider.models
        return (base + customModels).uniquedPreservingOrder()
    }

    func addCustomModel(_ model: String, for provider: AIProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        func add(to array: inout [String]) {
            let existing = Set(array.map { $0.lowercased() })
            guard !existing.contains(trimmed.lowercased()) else { return }
            array.insert(trimmed, at: 0)
        }

        switch provider {
        case .openAI:
            add(to: &customOpenAIModels)
        case .anthropic:
            add(to: &customAnthropicModels)
        case .gemini:
            add(to: &customGeminiModels)
        }
    }

    private func migrateSelectedAIModelIfNeeded() {
        let trimmed = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if AIProvider.openAI.models.contains(trimmed) ||
            AIProvider.anthropic.models.contains(trimmed) ||
            AIProvider.gemini.models.contains(trimmed) {
            return
        }

        addCustomModel(trimmed, for: selectedAIProvider)
    }

    private func ensureSelectedAIModelIsValid() {
        let models = availableModels(for: selectedAIProvider)
        let trimmed = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            selectedAIModel = models.first ?? ""
            return
        }

        if !models.contains(trimmed) {
            selectedAIModel = models.first ?? ""
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
        case .system: return "desktopcomputer"
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
            return [
                "gpt-5.1",
                "gpt-5-mini",
                "gpt-5-nano",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4.1-nano",
                "gpt-4o",
                "gpt-4o-mini",
                "o4-mini",
                "o3-mini"
            ]
        case .anthropic:
            return [
                "claude-sonnet-4-20250514",
                "claude-opus-4-1-20250805",
                "claude-opus-4-20250514",
                "claude-3-7-sonnet-latest",
                "claude-3-5-sonnet-latest",
                "claude-3-5-haiku-latest"
            ]
        case .gemini:
            return [
                "gemini-3-pro-preview",
                "gemini-3-pro",
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash",
                "gemini-2.0-flash-lite"
            ]
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

private extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        result.reserveCapacity(count)
        for value in self where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
