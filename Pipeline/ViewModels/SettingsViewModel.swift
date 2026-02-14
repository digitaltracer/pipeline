import Foundation
import SwiftUI
import PipelineKit

@Observable
final class SettingsViewModel {
    enum APIKeyValidationError: LocalizedError {
        case emptyKey
        case noCompatibleModels

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                return "API key cannot be empty."
            case .noCompatibleModels:
                return "No compatible models were returned for this key."
            }
        }
    }

    private enum StorageKeys {
        static let appearanceMode = "appearanceMode"
        static let selectedAIProvider = "selectedAIProvider"
        static let selectedAIModel = "selectedAIModel"
        static let cloudSyncEnabled = Constants.UserDefaultsKeys.cloudSyncEnabled

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

    // MARK: - Sync

    let cloudSyncSupported: Bool
    let cloudSyncEnabledAtLaunch: Bool

    var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: StorageKeys.cloudSyncEnabled)
        }
    }

    var cloudSyncNeedsRestart: Bool {
        cloudSyncEnabled != cloudSyncEnabledAtLaunch
    }

    // MARK: - Initialization

    init(
        cloudSyncSupported: Bool = true,
        cloudSyncEnabledAtLaunch: Bool? = nil
    ) {
        self.cloudSyncSupported = cloudSyncSupported
        let storedCloudSyncPreference = UserDefaults.standard.object(forKey: StorageKeys.cloudSyncEnabled) as? Bool
        let initialCloudSyncEnabled = cloudSyncSupported ? (storedCloudSyncPreference ?? true) : false
        self.cloudSyncEnabled = initialCloudSyncEnabled
        self.cloudSyncEnabledAtLaunch = cloudSyncEnabledAtLaunch ?? initialCloudSyncEnabled

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

    @MainActor
    func validateAndSaveAPIKey(_ rawAPIKey: String, for provider: AIProvider) async throws {
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw APIKeyValidationError.emptyKey
        }

        let models = try await ModelCatalogService.shared.fetchModels(for: provider, apiKey: apiKey)
        guard !models.isEmpty else {
            throw APIKeyValidationError.noCompatibleModels
        }

        try KeychainService.shared.saveAPIKey(apiKey, for: provider)

        cachedModelsByProviderID[provider.providerID] = models
        modelRefreshTimestampsByProviderID[provider.providerID] = Date().timeIntervalSince1970
        modelRefreshErrorsByProviderID[provider.providerID] = nil

        if selectedAIProvider == provider {
            ensureSelectedAIModelIsValid()
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
