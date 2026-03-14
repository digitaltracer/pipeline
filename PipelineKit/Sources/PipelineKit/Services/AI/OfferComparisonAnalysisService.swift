import Foundation

public struct OfferComparisonAIOutput: Equatable, Sendable {
    public let recommendationText: String
    public let negotiationText: String
    public let recommendationCitations: [AIWebSearchCitation]
    public let negotiationCitations: [AIWebSearchCitation]

    public init(
        recommendationText: String,
        negotiationText: String,
        recommendationCitations: [AIWebSearchCitation],
        negotiationCitations: [AIWebSearchCitation]
    ) {
        self.recommendationText = recommendationText
        self.negotiationText = negotiationText
        self.recommendationCitations = recommendationCitations
        self.negotiationCitations = negotiationCitations
    }
}

public enum OfferComparisonAnalysisService {
    public static func generate(
        provider: AIProvider,
        apiKey: String,
        model: String,
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication],
        scoringService: OfferComparisonScoringService = OfferComparisonScoringService()
    ) async throws -> OfferComparisonAIOutput {
        let evaluation = scoringService.evaluate(worksheet: worksheet, applications: applications)
        let selectedApplications = scoringService.selectedApplications(for: worksheet, from: applications)

        let recommendationResponse = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: recommendationSystemPrompt,
            userPrompt: makeRecommendationPrompt(
                worksheet: worksheet,
                applications: selectedApplications,
                evaluation: evaluation,
                scoringService: scoringService
            ),
            maxTokens: 1200,
            temperature: 0.4
        )

        let negotiationMaterial = try await makeNegotiationResearch(
            provider: provider,
            apiKey: apiKey,
            model: model,
            applications: selectedApplications
        )

        let negotiationResponse = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: negotiationSystemPrompt,
            userPrompt: makeNegotiationPrompt(
                worksheet: worksheet,
                applications: selectedApplications,
                evaluation: evaluation,
                researchSummary: negotiationMaterial.summary,
                scoringService: scoringService
            ),
            maxTokens: 1600,
            temperature: 0.35
        )

        return OfferComparisonAIOutput(
            recommendationText: recommendationResponse.text,
            negotiationText: negotiationResponse.text,
            recommendationCitations: [],
            negotiationCitations: negotiationMaterial.citations
        )
    }

    static func makeRecommendationPrompt(
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication],
        evaluation: OfferComparisonEvaluation,
        scoringService: OfferComparisonScoringService
    ) -> String {
        let factors = worksheet.sortedFactors.filter(\.isEnabled)
        let factorLines = factors.map { factor in
            let perOffer = applications.map { application in
                let value = scoringService.displayValue(for: factor, application: application)
                return "\(application.companyName): value=\(value.text), score=\(value.score.map(String.init) ?? "missing")"
            }.joined(separator: " | ")
            return "- \(factor.title) (weight \(factor.weight)): \(perOffer)"
        }.joined(separator: "\n")

        let ranking = evaluation.results.enumerated().map { index, result in
            "\(index + 1). \(result.companyName) - \(String(format: "%.2f", result.weightedAverage))/5"
        }.joined(separator: "\n")

        return """
        Offer comparison worksheet summary:
        - Recommendation is only valid when all active factors are scored.
        - Completion state: \(evaluation.isComplete ? "complete" : "incomplete")
        - Missing score count: \(evaluation.missingScoreCount)

        Active factors:
        \(factorLines)

        Calculated ranking:
        \(ranking.isEmpty ? "No ranking yet." : ranking)

        Selected offers:
        \(applications.map { "\($0.companyName) - \($0.role) in \($0.location)" }.joined(separator: "\n"))

        Write a concise mentor-style recommendation. Reference the user's weighted priorities, name the top offer, mention tradeoffs for the other offers, and avoid inventing facts not present above.
        """
    }

    static func makeNegotiationPrompt(
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication],
        evaluation: OfferComparisonEvaluation,
        researchSummary: String,
        scoringService: OfferComparisonScoringService
    ) -> String {
        let offers = applications.map { application in
            let rows = worksheet.sortedFactors.filter(\.isEnabled).map { factor in
                let value = scoringService.displayValue(for: factor, application: application)
                return "\(factor.title): \(value.text) (score \(value.score.map(String.init) ?? "missing"))"
            }.joined(separator: "\n")

            return """
            \(application.companyName) - \(application.role) - \(application.location)
            \(rows)
            """
        }.joined(separator: "\n\n")

        let internalBenchmarks = applications.map { application in
            let snapshots = application.company?.sortedSalarySnapshots.prefix(3) ?? []
            guard !snapshots.isEmpty else {
                return "\(application.companyName): No saved company salary snapshots."
            }

            let entries = snapshots.map { snapshot in
                let range = snapshot.totalRangeText ?? snapshot.baseRangeText ?? "—"
                return "\(snapshot.roleTitle) / \(snapshot.location) / \(range) / \(snapshot.sourceName)"
            }.joined(separator: "\n")

            return "\(application.companyName):\n\(entries)"
        }.joined(separator: "\n\n")

        let ranking = evaluation.results.enumerated().map { index, result in
            "\(index + 1). \(result.companyName) - \(String(format: "%.2f", result.weightedAverage))/5"
        }.joined(separator: "\n")

        return """
        Offer worksheet context:
        \(offers)

        Calculated ranking:
        \(ranking)

        Saved company salary snapshots:
        \(internalBenchmarks)

        Grounded compensation research:
        \(researchSummary)

        Write a practical negotiation helper. For each offer that appears negotiable, explain the market signal, the likely ask, and provide a short negotiation script. Call out uncertainty when evidence is weak. Do not fabricate market medians beyond the research summary.
        """
    }

    private static func makeNegotiationResearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        applications: [JobApplication]
    ) async throws -> (summary: String, citations: [AIWebSearchCitation]) {
        var sections: [String] = []
        var citations: [AIWebSearchCitation] = []

        for application in applications.prefix(4) {
            let query = makeNegotiationQuery(for: application)
            let response = try await AICompletionClient.groundedWebSearch(
                provider: provider,
                apiKey: apiKey,
                model: model,
                query: query,
                systemPrompt: negotiationSearchSystemPrompt,
                maxTokens: 700
            )

            sections.append("## \(application.companyName)\n\(response.text)")
            citations.append(contentsOf: response.citations.prefix(4))
        }

        return (summary: sections.joined(separator: "\n\n"), citations: deduplicatedCitations(citations))
    }

    static func makeNegotiationQuery(for application: JobApplication) -> String {
        "\(application.companyName) \(application.role) \(application.location) compensation median salary signing bonus equity negotiation"
    }

    private static func deduplicatedCitations(_ citations: [AIWebSearchCitation]) -> [AIWebSearchCitation] {
        var seen: Set<String> = []
        var result: [AIWebSearchCitation] = []

        for citation in citations {
            let key = citation.urlString.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(citation)
        }

        return result
    }

    private static let recommendationSystemPrompt = """
    You are a careful job-offer advisor. Use only the supplied worksheet data. Be concise, specific, and transparent about tradeoffs.
    """

    private static let negotiationSystemPrompt = """
    You are a compensation negotiation advisor. Use the grounded research provided in the prompt, distinguish evidence from inference, and produce respectful negotiation language.
    """

    private static let negotiationSearchSystemPrompt = """
    Search for recent compensation evidence for the exact company, role, and region. Prefer company, Levels.fyi, Glassdoor, Blind, and reputable compensation sources. Return concise evidence with citations.
    """
}
