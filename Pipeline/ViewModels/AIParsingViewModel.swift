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

    // Services
    private let settingsViewModel: SettingsViewModel

    init(settingsViewModel: SettingsViewModel = SettingsViewModel()) {
        self.settingsViewModel = settingsViewModel
    }

    var selectedProvider: AIProvider {
        settingsViewModel.selectedAIProvider
    }

    // MARK: - Configuration

    @MainActor
    func refreshConfiguration() {
        do {
            let apiKey = try KeychainService.shared.getAPIKey(for: settingsViewModel.selectedAIProvider)
            isConfigured = !apiKey.isEmpty
        } catch {
            isConfigured = false
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
    }

    // MARK: - Actions

    @MainActor
    func parseJobURL() async {
        refreshConfiguration()
        let trimmed = jobURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            error = "Please enter a job URL"
            return
        }

        let normalizedJobURL = URLHelpers.normalize(trimmed)
        guard URLHelpers.isValidWebURL(normalizedJobURL) else {
            error = "Invalid URL. Please use a valid http or https link."
            return
        }

        isLoading = true
        error = nil
        parsedData = nil
        defer { isLoading = false }

        do {
            // Get API key from Keychain
            let apiKey = try KeychainService.shared.getAPIKey(for: settingsViewModel.selectedAIProvider)

            guard !apiKey.isEmpty else {
                error = "API key not configured. Please set up your API key in Settings."
                return
            }

            // Create appropriate AI service
            let service = createAIService(provider: settingsViewModel.selectedAIProvider, apiKey: apiKey)

            // Fetch and parse the job posting
            let parsed = try await service.parseJobPosting(from: normalizedJobURL, model: settingsViewModel.selectedAIModel)
            parsedData = parsed

        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
        } catch {
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
