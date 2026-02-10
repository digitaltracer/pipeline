import Foundation
import SwiftUI

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

    // Services
    private let settingsViewModel: SettingsViewModel

    init(settingsViewModel: SettingsViewModel = SettingsViewModel()) {
        self.settingsViewModel = settingsViewModel
        self.parseProvider = settingsViewModel.selectedAIProvider
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

    // MARK: - Parsed Data

    struct ParsedJobData {
        var companyName: String
        var role: String
        var location: String
        var jobDescription: String
        var salaryMin: Int?
        var salaryMax: Int?
        var currency: Currency

        init(
            companyName: String = "",
            role: String = "",
            location: String = "",
            jobDescription: String = "",
            salaryMin: Int? = nil,
            salaryMax: Int? = nil,
            currency: Currency = .usd
        ) {
            self.companyName = companyName
            self.role = role
            self.location = location
            self.jobDescription = jobDescription
            self.salaryMin = salaryMin
            self.salaryMax = salaryMax
            self.currency = currency
        }

        var hasMeaningfulContent: Bool {
            !companyName.isEmpty ||
                !role.isEmpty ||
                !location.isEmpty ||
                !jobDescription.isEmpty ||
                salaryMin != nil ||
                salaryMax != nil
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

        isLoading = true
        error = nil
        parsedData = nil
        defer { isLoading = false }

        do {
            // Get API key from Keychain
            let apiKey = try KeychainService.shared.getAPIKey(for: parseProvider)

            guard !apiKey.isEmpty else {
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

            // Create appropriate AI service
            let service = createAIService(provider: parseProvider, apiKey: apiKey)
            AIParseDebugLogger.info(
                "AIParsingViewModel: invoking \(parseProvider.rawValue) service with model \(model)."
            )

            // Fetch and parse the job posting
            let parsed = try await service.parseJobPosting(from: normalizedJobURL, model: model)
            guard parsed.hasMeaningfulContent else {
                AIParseDebugLogger.warning(
                    "AIParsingViewModel: parse finished but extracted fields were empty."
                )
                throw AIServiceError.noDataExtracted
            }
            parsedData = parsed
            AIParseDebugLogger.info("AIParsingViewModel: parse completed successfully.")

        } catch let aiError as AIServiceError {
            AIParseDebugLogger.error(
                "AIParsingViewModel: parse failed with AIServiceError: \(aiError.localizedDescription)."
            )
            error = aiError.localizedDescription
        } catch {
            AIParseDebugLogger.error(
                "AIParsingViewModel: parse failed with unexpected error: \(error.localizedDescription)."
            )
            self.error = "Failed to parse job posting: \(error.localizedDescription)"
        }
    }

    private func createAIService(provider: AIProvider, apiKey: String) -> AIServiceProtocol {
        switch provider {
        case .openAI:
            return OpenAIService(apiKey: apiKey)
        case .anthropic:
            return AnthropicService(apiKey: apiKey)
        case .gemini:
            return GeminiService(apiKey: apiKey)
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

        // Auto-detect platform
        viewModel.platform = Platform.detect(from: jobURL)
    }

    // MARK: - Reset

    func reset() {
        jobURL = ""
        isLoading = false
        error = nil
        parsedData = nil
    }
}
