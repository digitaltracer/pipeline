import Foundation
import SwiftUI
import PipelineKit

@Observable
final class SettingsViewModel {
    enum APIKeyValidationError: LocalizedError {
        case emptyKey
        case noCompatibleModels
        case noConfiguredKeys(String)

        var errorDescription: String? {
            switch self {
            case .emptyKey:
                return "API key cannot be empty."
            case .noCompatibleModels:
                return "No compatible models were returned for this key."
            case .noConfiguredKeys(let providerName):
                return "No API key configured for \(providerName)."
            }
        }
    }

    private enum StorageKeys {
        static let appearanceMode = "appearanceMode"
        static let selectedAIProvider = "selectedAIProvider"
        static let selectedAIModel = "selectedAIModel"
        static let cloudSyncEnabled = Constants.UserDefaultsKeys.cloudSyncEnabled
        static let hiddenStatusesInAllApplications = "hiddenStatusesInAllApplications"

        static let customModelsByProviderID = "customModelsByProviderID"
        static let cachedModelsByProviderID = "cachedModelsByProviderID"
        static let modelRefreshTimestampsByProviderID = "modelRefreshTimestampsByProviderID"

        static let legacyCustomOpenAIModels = "customOpenAIModels"
        static let legacyCustomAnthropicModels = "customAnthropicModels"
        static let legacyCustomGeminiModels = "customGeminiModels"

        static let notificationsEnabled = "notificationsEnabled"
        static let reminderTiming = "reminderTiming"
        static let analyticsBaseCurrency = Constants.UserDefaultsKeys.analyticsBaseCurrency
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

    private var hiddenStatusesInAllApplications: [String] {
        didSet {
            UserDefaults.standard.set(hiddenStatusesInAllApplications, forKey: StorageKeys.hiddenStatusesInAllApplications)
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

    var analyticsBaseCurrency: Currency {
        didSet {
            UserDefaults.standard.set(analyticsBaseCurrency.rawValue, forKey: StorageKeys.analyticsBaseCurrency)
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
        self.hiddenStatusesInAllApplications = UserDefaults.standard.stringArray(
            forKey: StorageKeys.hiddenStatusesInAllApplications
        ) ?? []
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

        if let rawValue = UserDefaults.standard.string(forKey: StorageKeys.analyticsBaseCurrency),
           let currency = Currency(rawValue: rawValue) {
            self.analyticsBaseCurrency = currency
        } else {
            self.analyticsBaseCurrency = .usd
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

    func allApplicationsStatusOptions() -> [ApplicationStatus] {
        let defaults = ApplicationStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
        let customs = CustomValuesStore.customStatuses()
            .map { ApplicationStatus(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var seen = Set<String>()
        return (defaults + customs).filter { status in
            let key = normalizedStatusKey(status.rawValue)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    func isStatusVisibleInAllApplications(_ status: ApplicationStatus) -> Bool {
        !hiddenStatusLookup.contains(normalizedStatusKey(status.rawValue))
    }

    func setStatus(_ status: ApplicationStatus, visibleInAllApplications isVisible: Bool) {
        let key = normalizedStatusKey(status.rawValue)
        var hidden = hiddenStatusLookup

        if isVisible {
            hidden.remove(key)
        } else {
            hidden.insert(key)
        }

        hiddenStatusesInAllApplications = Array(hidden)
    }

    func resetAllApplicationsVisibilityToDefault() {
        hiddenStatusesInAllApplications = []
    }

    func shouldIncludeInAllApplications(_ application: JobApplication) -> Bool {
        !hiddenStatusLookup.contains(normalizedStatusKey(application.status.rawValue))
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        KeychainService.shared.hasAPIKey(for: provider)
    }

    func apiKeys(for provider: AIProvider) throws -> [String] {
        try KeychainService.shared.getAPIKeys(for: provider)
    }

    func removeAPIKey(_ apiKey: String, for provider: AIProvider) throws {
        try KeychainService.shared.removeAPIKey(apiKey, for: provider)
    }

    func setAPIKeys(_ apiKeys: [String], for provider: AIProvider) throws {
        try KeychainService.shared.setAPIKeys(apiKeys, for: provider)
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

        let keys: [String]
        do {
            keys = try apiKeys(for: provider)
        } catch {
            modelRefreshErrorsByProviderID[provider.providerID] = "Could not access API key."
            return
        }

        guard !keys.isEmpty else {
            return
        }

        refreshingProviderID = provider.providerID
        modelRefreshErrorsByProviderID[provider.providerID] = nil

        defer {
            refreshingProviderID = nil
        }

        do {
            let models = try await withAPIKeyWaterfall(for: provider) { apiKey in
                try await ModelCatalogService.shared.fetchModels(for: provider, apiKey: apiKey)
            }
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
    func validateAPIKeyConnection(_ rawAPIKey: String, for provider: AIProvider) async throws -> [String] {
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw APIKeyValidationError.emptyKey
        }

        let models = try await ModelCatalogService.shared.fetchModels(for: provider, apiKey: apiKey)
        guard !models.isEmpty else {
            throw APIKeyValidationError.noCompatibleModels
        }

        return models
    }

    @MainActor
    func saveValidatedAPIKey(_ rawAPIKey: String, models: [String], for provider: AIProvider) throws {
        let apiKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            throw APIKeyValidationError.emptyKey
        }

        let normalizedModels = models
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
        guard !normalizedModels.isEmpty else {
            throw APIKeyValidationError.noCompatibleModels
        }

        try KeychainService.shared.addAPIKey(apiKey, for: provider)

        cachedModelsByProviderID[provider.providerID] = normalizedModels
        modelRefreshTimestampsByProviderID[provider.providerID] = Date().timeIntervalSince1970
        modelRefreshErrorsByProviderID[provider.providerID] = nil

        if selectedAIProvider == provider {
            ensureSelectedAIModelIsValid()
        }
    }

    @MainActor
    func validateAndSaveAPIKey(_ rawAPIKey: String, for provider: AIProvider) async throws {
        let models = try await validateAPIKeyConnection(rawAPIKey, for: provider)
        try saveValidatedAPIKey(rawAPIKey, models: models, for: provider)
    }

    @MainActor
    func withAPIKeyWaterfall<T>(
        for provider: AIProvider,
        operation: (String) async throws -> T
    ) async throws -> T {
        let keys = try apiKeys(for: provider)
        guard !keys.isEmpty else {
            throw APIKeyValidationError.noConfiguredKeys(provider.rawValue)
        }

        var lastError: Error?

        for (index, key) in keys.enumerated() {
            do {
                return try await operation(key)
            } catch {
                lastError = error
                let hasMoreKeys = index < keys.count - 1
                guard hasMoreKeys, shouldFallbackToNextKey(after: error) else {
                    throw error
                }
            }
        }

        if let lastError {
            throw lastError
        }

        throw APIKeyValidationError.noConfiguredKeys(provider.rawValue)
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

    private func shouldFallbackToNextKey(after error: Error) -> Bool {
        guard let aiError = error as? AIServiceError else {
            return false
        }

        switch aiError {
        case .unauthorized, .rateLimited:
            return true
        case .apiError(let message):
            return isLikelyAPIKeyFailure(message)
        default:
            return false
        }
    }

    private func isLikelyAPIKeyFailure(_ message: String) -> Bool {
        let lowered = message.lowercased()
        let indicators = [
            "invalid api key",
            "incorrect api key",
            "unauthorized",
            "forbidden",
            "quota",
            "rate limit",
            "insufficient",
            "billing",
            "credit",
            "permission denied",
            "authentication"
        ]
        return indicators.contains(where: lowered.contains)
    }

    private var hiddenStatusLookup: Set<String> {
        Set(hiddenStatusesInAllApplications.map(normalizedStatusKey))
    }

    private func normalizedStatusKey(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
