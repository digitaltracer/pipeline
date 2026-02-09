import Foundation
import SwiftUI

@Observable
final class SettingsViewModel {
    private enum StorageKeys {
        static let appearanceMode = "appearanceMode"
        static let selectedAIProvider = "selectedAIProvider"
        static let selectedAIModel = "selectedAIModel"

        static let customModelsByProviderID = "customModelsByProviderID"
        static let cachedModelsByProviderID = "cachedModelsByProviderID"
        static let modelRefreshTimestampsByProviderID = "modelRefreshTimestampsByProviderID"

        static let legacyCustomOpenAIModels = "customOpenAIModels"
        static let legacyCustomAnthropicModels = "customAnthropicModels"
        static let legacyCustomGeminiModels = "customGeminiModels"

        static let notificationsEnabled = "notificationsEnabled"
        static let reminderTiming = "reminderTiming"
    }

    private static let modelCatalogRefreshInterval: TimeInterval = 60 * 60 * 24

    // MARK: - Appearance

    var appearanceMode: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: StorageKeys.appearanceMode)
        }
    }

    // MARK: - AI Provider

    var selectedAIProvider: AIProvider {
        didSet {
            UserDefaults.standard.set(selectedAIProvider.rawValue, forKey: StorageKeys.selectedAIProvider)
            ensureSelectedAIModelIsValid()
        }
    }

    var selectedAIModel: String {
        didSet {
            UserDefaults.standard.set(selectedAIModel, forKey: StorageKeys.selectedAIModel)
        }
    }

    private var customModelsByProviderID: [String: [String]] {
        didSet {
            UserDefaults.standard.set(customModelsByProviderID, forKey: StorageKeys.customModelsByProviderID)
        }
    }

    private var cachedModelsByProviderID: [String: [String]] {
        didSet {
            UserDefaults.standard.set(cachedModelsByProviderID, forKey: StorageKeys.cachedModelsByProviderID)
        }
    }

    private var modelRefreshTimestampsByProviderID: [String: TimeInterval] {
        didSet {
            UserDefaults.standard.set(modelRefreshTimestampsByProviderID, forKey: StorageKeys.modelRefreshTimestampsByProviderID)
        }
    }

    private(set) var refreshingProviderID: String?
    private(set) var modelRefreshErrorsByProviderID: [String: String] = [:]

    // MARK: - Notifications

    var notificationsEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notificationsEnabled, forKey: StorageKeys.notificationsEnabled)
        }
    }

    var reminderTiming: ReminderTiming {
        didSet {
            UserDefaults.standard.set(reminderTiming.rawValue, forKey: StorageKeys.reminderTiming)
        }
    }

    // MARK: - Initialization

    init() {
        if let rawValue = UserDefaults.standard.string(forKey: StorageKeys.appearanceMode),
           let mode = AppearanceMode(rawValue: rawValue) {
            self.appearanceMode = mode
        } else {
            self.appearanceMode = .system
        }

        if let rawValue = UserDefaults.standard.string(forKey: StorageKeys.selectedAIProvider),
           let provider = AIProvider(rawValue: rawValue) {
            self.selectedAIProvider = provider
        } else {
            self.selectedAIProvider = .openAI
        }

        self.selectedAIModel = UserDefaults.standard.string(forKey: StorageKeys.selectedAIModel) ?? ""
        self.customModelsByProviderID = Self.loadStringArrayDictionary(forKey: StorageKeys.customModelsByProviderID)
        self.cachedModelsByProviderID = Self.loadStringArrayDictionary(forKey: StorageKeys.cachedModelsByProviderID)
        self.modelRefreshTimestampsByProviderID = Self.loadTimestampDictionary(
            forKey: StorageKeys.modelRefreshTimestampsByProviderID
        )

        self.notificationsEnabled = UserDefaults.standard.bool(forKey: StorageKeys.notificationsEnabled)

        if let rawValue = UserDefaults.standard.string(forKey: StorageKeys.reminderTiming),
           let timing = ReminderTiming(rawValue: rawValue) {
            self.reminderTiming = timing
        } else {
            self.reminderTiming = .dayBefore
        }

        migrateLegacyCustomModelStorageIfNeeded()
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
        let base = baseModels(for: provider)
        let custom = customModelsByProviderID[provider.providerID] ?? []
        return (base + custom).uniquedPreservingOrder()
    }

    func preferredModel(for provider: AIProvider) -> String {
        let models = availableModels(for: provider)
        guard !models.isEmpty else { return "" }

        if provider == selectedAIProvider {
            let selected = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
            if models.contains(selected) {
                return selected
            }
        }

        return models.first ?? ""
    }

    func addCustomModel(_ model: String, for provider: AIProvider) {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var models = customModelsByProviderID[provider.providerID] ?? []
        let existing = Set(models.map { $0.lowercased() })
        guard !existing.contains(trimmed.lowercased()) else { return }

        models.insert(trimmed, at: 0)
        customModelsByProviderID[provider.providerID] = models
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        KeychainService.shared.hasAPIKey(for: provider)
    }

    func isRefreshingModels(for provider: AIProvider) -> Bool {
        refreshingProviderID == provider.providerID
    }

    func modelRefreshError(for provider: AIProvider) -> String? {
        modelRefreshErrorsByProviderID[provider.providerID]
    }

    func lastModelRefreshDate(for provider: AIProvider) -> Date? {
        guard let timestamp = modelRefreshTimestampsByProviderID[provider.providerID] else {
            return nil
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    @MainActor
    func refreshModelsIfNeeded(for provider: AIProvider) async {
        guard shouldRefreshModels(for: provider) else { return }
        await refreshModels(for: provider, force: false)
    }

    @MainActor
    func refreshModels(for provider: AIProvider, force: Bool = true) async {
        guard refreshingProviderID == nil else { return }
        guard force || shouldRefreshModels(for: provider) else { return }

        let apiKey: String
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
        } catch {
            modelRefreshErrorsByProviderID[provider.providerID] = "Could not access API key."
            return
        }

        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        refreshingProviderID = provider.providerID
        modelRefreshErrorsByProviderID[provider.providerID] = nil

        defer {
            refreshingProviderID = nil
        }

        do {
            let models = try await ModelCatalogService.shared.fetchModels(for: provider, apiKey: apiKey)
            guard !models.isEmpty else {
                modelRefreshErrorsByProviderID[provider.providerID] = "No compatible models were returned."
                return
            }

            cachedModelsByProviderID[provider.providerID] = models
            modelRefreshTimestampsByProviderID[provider.providerID] = Date().timeIntervalSince1970

            if selectedAIProvider == provider {
                ensureSelectedAIModelIsValid()
            }
        } catch let aiError as AIServiceError {
            modelRefreshErrorsByProviderID[provider.providerID] = aiError.localizedDescription
        } catch {
            modelRefreshErrorsByProviderID[provider.providerID] = "Could not refresh models. Using saved list."
        }
    }

    // MARK: - Private

    private func baseModels(for provider: AIProvider) -> [String] {
        let cached = (cachedModelsByProviderID[provider.providerID] ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()

        if !cached.isEmpty {
            return cached
        }

        return provider.defaultModels
    }

    private func shouldRefreshModels(for provider: AIProvider) -> Bool {
        if (cachedModelsByProviderID[provider.providerID] ?? []).isEmpty {
            return true
        }

        guard let lastRefreshTimestamp = modelRefreshTimestampsByProviderID[provider.providerID] else {
            return true
        }

        let age = Date().timeIntervalSince1970 - lastRefreshTimestamp
        return age >= Self.modelCatalogRefreshInterval
    }

    private func migrateLegacyCustomModelStorageIfNeeded() {
        let legacyMappings: [(AIProvider, String)] = [
            (.openAI, StorageKeys.legacyCustomOpenAIModels),
            (.anthropic, StorageKeys.legacyCustomAnthropicModels),
            (.gemini, StorageKeys.legacyCustomGeminiModels)
        ]

        for (provider, key) in legacyMappings {
            let existing = customModelsByProviderID[provider.providerID] ?? []
            guard existing.isEmpty else { continue }

            let legacyModels = UserDefaults.standard.stringArray(forKey: key) ?? []
            let normalized = legacyModels
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .uniquedPreservingOrder()

            if !normalized.isEmpty {
                customModelsByProviderID[provider.providerID] = normalized
            }

            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func migrateSelectedAIModelIfNeeded() {
        let trimmed = selectedAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let isKnown = AIProvider.allCases.contains { provider in
            availableModels(for: provider).contains(trimmed)
        }

        guard !isKnown else { return }

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

    private static func loadStringArrayDictionary(forKey key: String) -> [String: [String]] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else {
            return [:]
        }

        var result: [String: [String]] = [:]
        for (dictKey, value) in raw {
            if let array = value as? [String] {
                result[dictKey] = array
            }
        }
        return result
    }

    private static func loadTimestampDictionary(forKey key: String) -> [String: TimeInterval] {
        guard let raw = UserDefaults.standard.dictionary(forKey: key) else {
            return [:]
        }

        var result: [String: TimeInterval] = [:]
        for (dictKey, value) in raw {
            if let interval = value as? TimeInterval {
                result[dictKey] = interval
                continue
            }

            if let number = value as? NSNumber {
                result[dictKey] = number.doubleValue
            }
        }
        return result
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

    var id: String { providerID }

    var descriptor: AIProviderDescriptor {
        AIProviderRegistry.descriptor(for: self)
    }

    var providerID: String { descriptor.providerID }
    var icon: String { descriptor.icon }
    var defaultModels: [String] { descriptor.defaultModels }
    var models: [String] { defaultModels }
    var keychainKey: String { descriptor.keychainAccount }
    var aboutText: String { descriptor.aboutText }
    var apiKeyURL: String { descriptor.apiKeyURL }
}

struct AIProviderDescriptor {
    let provider: AIProvider
    let providerID: String
    let icon: String
    let keychainAccount: String
    let aboutText: String
    let apiKeyURL: String
    let defaultModels: [String]
}

enum AIProviderRegistry {
    static let allDescriptors: [AIProviderDescriptor] = [
        AIProviderDescriptor(
            provider: .openAI,
            providerID: "openai",
            icon: "brain",
            keychainAccount: "com.pipeline.openai-api-key",
            aboutText: "OpenAI provides GPT and reasoning models for job posting parsing.",
            apiKeyURL: "https://platform.openai.com/api-keys",
            defaultModels: [
                "gpt-5",
                "gpt-5-mini",
                "gpt-4.1",
                "gpt-4o",
                "o4-mini"
            ]
        ),
        AIProviderDescriptor(
            provider: .anthropic,
            providerID: "anthropic",
            icon: "sparkles",
            keychainAccount: "com.pipeline.anthropic-api-key",
            aboutText: "Anthropic provides Claude models with strong reasoning and structured output.",
            apiKeyURL: "https://console.anthropic.com/",
            defaultModels: [
                "claude-sonnet-4-5",
                "claude-opus-4-1",
                "claude-sonnet-4",
                "claude-3-7-sonnet-latest",
                "claude-3-5-haiku-latest"
            ]
        ),
        AIProviderDescriptor(
            provider: .gemini,
            providerID: "gemini",
            icon: "wand.and.stars",
            keychainAccount: "com.pipeline.gemini-api-key",
            aboutText: "Google Gemini offers fast and capable multimodal models.",
            apiKeyURL: "https://ai.google.dev/aistudio",
            defaultModels: [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash",
                "gemini-2.0-flash-lite"
            ]
        )
    ]

    static func descriptor(for provider: AIProvider) -> AIProviderDescriptor {
        allDescriptors.first { $0.provider == provider } ?? allDescriptors[0]
    }
}

final class ModelCatalogService {
    static let shared = ModelCatalogService()

    private init() {}

    func fetchModels(for provider: AIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .openAI:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
        }
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isOpenAIChatCompatibleModel($0) }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func fetchAnthropicModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().contains("claude") }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw AIServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components.url else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { model -> String? in
                guard let name = model["name"] as? String else { return nil }

                let methods = model["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent") else { return nil }

                if name.hasPrefix("models/") {
                    return String(name.dropFirst("models/".count))
                }

                return name
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().contains("gemini") }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func requestData(
        _ request: URLRequest,
        unauthorizedStatusCodes: Set<Int>
    ) async throws -> Data {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if unauthorizedStatusCodes.contains(httpResponse.statusCode) {
            throw AIServiceError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError.apiError(message)
        }

        return data
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private func isOpenAIChatCompatibleModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()

        let disallowedSubstrings = [
            "embedding",
            "whisper",
            "transcribe",
            "tts",
            "audio",
            "realtime",
            "image",
            "moderation",
            "dall-e",
            "search",
            "rerank"
        ]

        if disallowedSubstrings.contains(where: lower.contains) {
            return false
        }

        if lower.hasPrefix("gpt") || lower.hasPrefix("chatgpt") {
            return true
        }

        if lower.range(of: #"^o\d"#, options: .regularExpression) != nil {
            return true
        }

        return false
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
