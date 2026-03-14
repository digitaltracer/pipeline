import Foundation

public struct ApplicationNegotiationGuidanceOutput: Sendable, Equatable {
    public let text: String
    public let suggestedCounterMin: Int?
    public let suggestedCounterMax: Int?
    public let citations: [AIWebSearchCitation]

    public init(
        text: String,
        suggestedCounterMin: Int?,
        suggestedCounterMax: Int?,
        citations: [AIWebSearchCitation]
    ) {
        self.text = text
        self.suggestedCounterMin = suggestedCounterMin
        self.suggestedCounterMax = suggestedCounterMax
        self.citations = citations
    }
}

public protocol ApplicationNegotiationResearchProviding: Sendable {
    func groundedWebSearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse
}

public protocol ApplicationNegotiationCompletionProviding: Sendable {
    func complete(
        provider: AIProvider,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AICompletionResponse
}

public struct DefaultApplicationNegotiationResearchProvider: ApplicationNegotiationResearchProviding {
    public init() {}

    public func groundedWebSearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse {
        try await AICompletionClient.groundedWebSearch(
            provider: provider,
            apiKey: apiKey,
            model: model,
            query: query,
            systemPrompt: systemPrompt,
            domains: domains,
            maxTokens: maxTokens
        )
    }
}

public struct DefaultApplicationNegotiationCompletionProvider: ApplicationNegotiationCompletionProviding {
    public init() {}

    public func complete(
        provider: AIProvider,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AICompletionResponse {
        try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens,
            temperature: temperature
        )
    }
}

public enum ApplicationNegotiationGuidanceService {
    public static func isSupported(provider: AIProvider, model: String) -> Bool {
        AICompletionClient.supportsWebSearch(provider: provider, model: model)
    }

    public static func generate(
        provider: AIProvider,
        apiKey: String,
        model: String,
        application: JobApplication,
        benchmark: MarketSalaryBenchmarkResult,
        savedSnapshots: [CompanySalarySnapshot],
        researchProvider: ApplicationNegotiationResearchProviding = DefaultApplicationNegotiationResearchProvider(),
        completionProvider: ApplicationNegotiationCompletionProviding = DefaultApplicationNegotiationCompletionProvider()
    ) async throws -> ApplicationNegotiationGuidanceOutput {
        guard isSupported(provider: provider, model: model) else {
            throw AIServiceError.apiError("The selected AI model does not support grounded web search.")
        }

        let research = try await researchProvider.groundedWebSearch(
            provider: provider,
            apiKey: apiKey,
            model: model,
            query: makeNegotiationQuery(for: application),
            systemPrompt: negotiationSearchSystemPrompt,
            domains: [],
            maxTokens: 900
        )

        let suggestedCounter = suggestedCounterRange(
            currentCompensation: benchmark.currentCompensation,
            percentile50: benchmark.percentile50,
            percentile75: benchmark.percentile75
        )

        let response = try await completionProvider.complete(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: negotiationSystemPrompt,
            userPrompt: makePrompt(
                application: application,
                benchmark: benchmark,
                savedSnapshots: savedSnapshots,
                researchSummary: research.text,
                suggestedCounterMin: suggestedCounter.min,
                suggestedCounterMax: suggestedCounter.max
            ),
            maxTokens: 1_400,
            temperature: 0.35
        )

        return ApplicationNegotiationGuidanceOutput(
            text: response.text,
            suggestedCounterMin: suggestedCounter.min,
            suggestedCounterMax: suggestedCounter.max,
            citations: deduplicatedCitations(research.citations)
        )
    }

    public static func suggestedCounterRange(
        currentCompensation: Int?,
        percentile50: Int,
        percentile75: Int
    ) -> (min: Int?, max: Int?) {
        guard percentile50 > 0, percentile75 >= percentile50 else {
            return (nil, nil)
        }

        guard let currentCompensation else {
            return (percentile50, percentile75)
        }

        if currentCompensation < percentile50 {
            return (percentile50, percentile75)
        }

        if currentCompensation < percentile75 {
            return (currentCompensation, percentile75)
        }

        let modestAsk = Int((Double(currentCompensation) * 1.05).rounded())
        let stretchAsk = Int((Double(currentCompensation) * 1.1).rounded())
        return (modestAsk, max(stretchAsk, percentile75))
    }

    static func makeNegotiationQuery(for application: JobApplication) -> String {
        "\(application.companyName) \(application.role) \(application.location) compensation salary total pay negotiation"
    }

    static func makePrompt(
        application: JobApplication,
        benchmark: MarketSalaryBenchmarkResult,
        savedSnapshots: [CompanySalarySnapshot],
        researchSummary: String,
        suggestedCounterMin: Int?,
        suggestedCounterMax: Int?
    ) -> String {
        let snapshotLines = savedSnapshots
            .prefix(4)
            .map { snapshot in
                let rangeText = snapshot.totalRangeText ?? snapshot.baseRangeText ?? "—"
                return "- \(snapshot.roleTitle) / \(snapshot.location) / \(rangeText) / \(snapshot.sourceName)"
            }
            .joined(separator: "\n")

        let counterText: String
        if let suggestedCounterMin, let suggestedCounterMax {
            counterText = "\(benchmark.baseCurrency.format(suggestedCounterMin))-\(benchmark.baseCurrency.format(suggestedCounterMax))"
        } else {
            counterText = "No deterministic counter range available."
        }

        return """
        Application:
        - Company: \(application.companyName)
        - Role: \(application.role)
        - Location: \(application.location)
        - Seniority: \(benchmark.seniority.title)
        - Basis: \(benchmark.comparisonBasis.title)

        Market benchmark:
        - Match tier: \(benchmark.matchTier.title)
        - Confidence: \(benchmark.confidence.title)
        - Cohort size: \(benchmark.cohortCount)
        - 25th percentile: \(benchmark.baseCurrency.format(benchmark.percentile25))
        - Median: \(benchmark.baseCurrency.format(benchmark.percentile50))
        - 75th percentile: \(benchmark.baseCurrency.format(benchmark.percentile75))
        - Comparison: \(benchmark.comparisonText)
        - Suggested counter range: \(counterText)

        Saved salary snapshots:
        \(snapshotLines.isEmpty ? "- None saved." : snapshotLines)

        Grounded research:
        \(researchSummary)

        Write a concise negotiation helper with:
        1. A one-line recommendation on whether to negotiate.
        2. Two data-backed talking points.
        3. A short first-person negotiation script.
        4. A fallback script if the recruiter says compensation is fixed.
        Separate evidence from inference and do not invent uncited salary claims beyond the benchmark and research above.
        """
    }

    private static func deduplicatedCitations(_ citations: [AIWebSearchCitation]) -> [AIWebSearchCitation] {
        var seen: Set<String> = []
        var deduplicated: [AIWebSearchCitation] = []

        for citation in citations {
            let key = citation.urlString.lowercased()
            guard seen.insert(key).inserted else { continue }
            deduplicated.append(citation)
        }

        return deduplicated
    }

    private static let negotiationSystemPrompt = """
    You are a compensation negotiation advisor. Use only the supplied benchmark and grounded research. Keep the tone practical, respectful, and specific.
    """

    private static let negotiationSearchSystemPrompt = """
    Search for recent compensation evidence for the exact company, role, and region. Prefer company pages, Levels.fyi, Glassdoor, LinkedIn Salary, and other reputable compensation sources. Return concise evidence with citations.
    """
}
