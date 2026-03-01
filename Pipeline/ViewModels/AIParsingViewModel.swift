import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class AIParsingViewModel {
    // Input
    var jobURL: String = ""

    // State
    var isLoading: Bool = false
    var error: String?
    var parsedData: ParsedJobData?
    var isConfigured: Bool = false
    private(set) var configuredProviders: [AIProvider] = []
    var parseProvider: AIProvider
    var parseModel: String {
        settingsViewModel.preferredModel(for: parseProvider)
    }
    var modelContext: ModelContext?

    // Services
    private let settingsViewModel: SettingsViewModel

    init(
        settingsViewModel: SettingsViewModel = SettingsViewModel(),
        modelContext: ModelContext? = nil
    ) {
        self.settingsViewModel = settingsViewModel
        self.parseProvider = settingsViewModel.selectedAIProvider
        self.modelContext = modelContext
    }

    // MARK: - Configuration

    @MainActor
    func refreshConfiguration() {
        configuredProviders = AIProvider.allCases.filter { settingsViewModel.hasAPIKey(for: $0) }
        isConfigured = !configuredProviders.isEmpty

        guard isConfigured else {
            parseProvider = settingsViewModel.selectedAIProvider
            return
        }

        if configuredProviders.contains(parseProvider) {
            return
        }

        if configuredProviders.contains(settingsViewModel.selectedAIProvider) {
            parseProvider = settingsViewModel.selectedAIProvider
        } else if let firstConfiguredProvider = configuredProviders.first {
            parseProvider = firstConfiguredProvider
        }
    }

    // MARK: - Actions

    @MainActor
    func parseJobURL() async {
        refreshConfiguration()
        let trimmed = jobURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = parseModel

        AIParseDebugLogger.info(
            "AIParsingViewModel: parse requested provider=\(parseProvider.rawValue) model=\(model) url=\(AIParseDebugLogger.summarizedURL(trimmed))."
        )

        guard !trimmed.isEmpty else {
            error = "Please enter a job URL"
            AIParseDebugLogger.warning("AIParsingViewModel: parse blocked because URL input is empty.")
            return
        }

        let normalizedJobURL = URLHelpers.normalize(trimmed)
        guard URLHelpers.isValidWebURL(normalizedJobURL) else {
            error = "Invalid URL. Please use a valid http or https link."
            AIParseDebugLogger.warning(
                "AIParsingViewModel: parse blocked due to invalid URL: \(normalizedJobURL)."
            )
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        parsedData = nil
        defer { isLoading = false }

        do {
            let keys = try settingsViewModel.apiKeys(for: parseProvider)
            guard !keys.isEmpty else {
                error = "API key not configured. Please set up your API key in Settings."
                AIParseDebugLogger.warning(
                    "AIParsingViewModel: no API key configured for provider \(parseProvider.rawValue)."
                )
                return
            }

            guard !model.isEmpty else {
                error = "No compatible model available for \(parseProvider.rawValue)."
                AIParseDebugLogger.warning(
                    "AIParsingViewModel: no compatible model configured for provider \(parseProvider.rawValue)."
                )
                return
            }

            let parsed = try await settingsViewModel.withAPIKeyWaterfall(for: parseProvider) { apiKey in
                let service = createAIService(provider: parseProvider, apiKey: apiKey)
                AIParseDebugLogger.info(
                    "AIParsingViewModel: invoking \(parseProvider.rawValue) service with model \(model)."
                )
                return try await service.parseJobPosting(from: normalizedJobURL, model: model)
            }
            guard parsed.hasMeaningfulContent else {
                AIParseDebugLogger.warning(
                    "AIParsingViewModel: parse finished but extracted fields were empty."
                )
                throw AIServiceError.noDataExtracted
            }
            parsedData = parsed
            AIParseDebugLogger.info("AIParsingViewModel: parse completed successfully.")
            recordUsage(
                provider: parseProvider,
                model: model,
                usage: parsed.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )

        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                provider: parseProvider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            AIParseDebugLogger.error(
                "AIParsingViewModel: parse failed with AIServiceError: \(aiError.localizedDescription)."
            )
            error = aiError.localizedDescription
            recordUsage(
                provider: parseProvider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            AIParseDebugLogger.error(
                "AIParsingViewModel: parse failed with unexpected error: \(error.localizedDescription)."
            )
            self.error = "Failed to parse job posting: \(error.localizedDescription)"
            recordUsage(
                provider: parseProvider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
        }
    }

    private func createAIService(provider: AIProvider, apiKey: String) -> AIServiceProtocol {
        let contentProvider = WKWebViewContentProvider(serviceName: "\(provider.rawValue)Service")
        switch provider {
        case .openAI:
            return OpenAIService(apiKey: apiKey, contentProvider: contentProvider)
        case .anthropic:
            return AnthropicService(apiKey: apiKey, contentProvider: contentProvider)
        case .gemini:
            return GeminiService(apiKey: apiKey, contentProvider: contentProvider)
        }
    }

    // MARK: - Apply to Form

    func applyToViewModel(_ viewModel: AddEditApplicationViewModel) {
        guard let data = parsedData else { return }

        viewModel.companyName = data.companyName
        viewModel.role = data.role
        viewModel.location = data.location
        viewModel.jobDescription = data.jobDescription
        viewModel.jobURL = jobURL
        viewModel.currency = data.currency

        if let min = data.salaryMin {
            viewModel.salaryMinString = String(min)
        }
        if let max = data.salaryMax {
            viewModel.salaryMaxString = String(max)
        }

        viewModel.platform = Platform.detect(from: jobURL)
    }

    // MARK: - Reset

    func reset() {
        jobURL = ""
        isLoading = false
        error = nil
        parsedData = nil
    }

    private func recordUsage(
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: .jobParsing,
            provider: provider,
            model: model,
            usage: usage,
            status: status,
            applicationID: nil,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }
}
