import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class AIParsingViewModel {
    struct BatchParseResult: Identifiable {
        enum State {
            case pending
            case parsing
            case parsed(ParsedJobData)
            case needsBrowser(String)
            case failed(String)
        }

        let id = UUID()
        let url: String
        var state: State = .pending
    }

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
    var batchResults: [BatchParseResult] = []
    var browserHandoffURL: String?
    var waitingForBrowserCapture: Bool = false
    var pendingBrowserImport: PendingJobImport?

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
        let urls = normalizedInputURLs()
        if urls.count > 1 {
            await parseBatch(urls)
            return
        }

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

            let parsed = try await parse(input: .url(normalizedJobURL), model: model)
            guard parsed.hasMeaningfulContent else {
                AIParseDebugLogger.warning(
                    "AIParsingViewModel: parse finished but extracted fields were empty."
                )
                throw AIServiceError.noDataExtracted
            }
            parsedData = parsed
            browserHandoffURL = nil
            waitingForBrowserCapture = false
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
            markBrowserHandoffAvailable(for: normalizedJobURL, error: aiError)
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
            browserHandoffURL = normalizedJobURL
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

    @MainActor
    func parsePendingBrowserImport() async {
        guard let pendingBrowserImport else { return }
        await parseCapturedPage(pendingBrowserImport.capturedPage, removeWhenDone: pendingBrowserImport.id)
    }

    @MainActor
    func refreshPendingBrowserImport() {
        guard let latest = PendingJobImportService.loadLatest() else { return }
        pendingBrowserImport = latest
        waitingForBrowserCapture = false
        browserHandoffURL = nil
        jobURL = latest.capturedPage.url
        error = nil
    }

    @MainActor
    func beginBrowserHandoff() {
        waitingForBrowserCapture = browserHandoffURL != nil
    }

    @MainActor
    func selectBatchResult(_ result: BatchParseResult) {
        guard case .parsed(let parsed) = result.state else { return }
        jobURL = result.url
        parsedData = parsed
        error = nil
    }

    @MainActor
    private func parseBatch(_ urls: [String]) async {
        refreshConfiguration()
        let model = parseModel
        batchResults = urls.map { BatchParseResult(url: $0) }
        parsedData = nil
        error = nil
        browserHandoffURL = nil

        guard isConfigured else {
            error = "API key not configured. Please set up your API key in Settings."
            return
        }

        guard !model.isEmpty else {
            error = "No compatible model available for \(parseProvider.rawValue)."
            return
        }

        isLoading = true
        defer { isLoading = false }

        for index in batchResults.indices {
            let url = batchResults[index].url
            batchResults[index].state = .parsing
            let requestStartedAt = Date()

            do {
                let parsed = try await parse(input: .url(url), model: model)
                guard parsed.hasMeaningfulContent else {
                    throw AIServiceError.noDataExtracted
                }
                batchResults[index].state = .parsed(parsed)
                if parsedData == nil {
                    parsedData = parsed
                    jobURL = url
                }
                recordUsage(
                    provider: parseProvider,
                    model: model,
                    usage: parsed.usage,
                    status: .succeeded,
                    startedAt: requestStartedAt,
                    errorMessage: nil
                )
            } catch let aiError as AIServiceError {
                if shouldOfferBrowserHandoff(for: aiError) {
                    batchResults[index].state = .needsBrowser(aiError.localizedDescription)
                    browserHandoffURL = browserHandoffURL ?? url
                } else {
                    batchResults[index].state = .failed(aiError.localizedDescription)
                }
                recordUsage(
                    provider: parseProvider,
                    model: model,
                    usage: nil,
                    status: .failed,
                    startedAt: requestStartedAt,
                    errorMessage: aiError.localizedDescription
                )
            } catch {
                batchResults[index].state = .failed(error.localizedDescription)
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
    }

    @MainActor
    private func parseCapturedPage(_ page: JobCapturedPage, removeWhenDone importID: UUID?) async {
        refreshConfiguration()
        let model = parseModel
        let requestStartedAt = Date()

        guard isConfigured else {
            error = "API key not configured. Please set up your API key in Settings."
            return
        }

        guard !model.isEmpty else {
            error = "No compatible model available for \(parseProvider.rawValue)."
            return
        }

        isLoading = true
        error = nil
        parsedData = nil
        defer { isLoading = false }

        do {
            let parsed = try await parse(input: .capturedPage(page), model: model)
            guard parsed.hasMeaningfulContent else {
                throw AIServiceError.noDataExtracted
            }
            parsedData = parsed
            jobURL = page.url
            pendingBrowserImport = nil
            if let importID {
                PendingJobImportService.remove(id: importID)
            }
            recordUsage(
                provider: parseProvider,
                model: model,
                usage: parsed.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch {
            self.error = "Failed to parse captured browser content: \(error.localizedDescription)"
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

    private func parse(input: JobParseInput, model: String) async throws -> ParsedJobData {
        try await settingsViewModel.withAPIKeyWaterfall(for: parseProvider) { apiKey in
            let service = createAIService(provider: parseProvider, apiKey: apiKey)
            AIParseDebugLogger.info(
                "AIParsingViewModel: invoking \(parseProvider.rawValue) service with model \(model)."
            )
            return try await service.parseJobPosting(input: input, model: model)
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
        batchResults = []
        browserHandoffURL = nil
        waitingForBrowserCapture = false
        pendingBrowserImport = nil
    }

    private func normalizedInputURLs() -> [String] {
        jobURL
            .split(whereSeparator: \.isNewline)
            .map { URLHelpers.normalize(String($0).trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
    }

    private func markBrowserHandoffAvailable(for url: String, error: AIServiceError) {
        guard shouldOfferBrowserHandoff(for: error) else { return }
        browserHandoffURL = url
    }

    private func shouldOfferBrowserHandoff(for error: AIServiceError) -> Bool {
        switch error {
        case .apiError, .parsingError, .noDataExtracted, .networkError:
            return true
        case .invalidURL, .invalidResponse, .rateLimited, .unauthorized:
            return false
        }
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
