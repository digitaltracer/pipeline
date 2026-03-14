import Foundation
import Testing
@testable import PipelineKit

@Test func seniorityInferenceAndOverridePrecedence() {
    let application = JobApplication(
        companyName: "Example",
        role: "Senior Backend Engineer",
        location: "Remote"
    )

    #expect(application.inferredSeniority == .senior)
    #expect(application.effectiveSeniority == .senior)
    #expect(application.normalizedRoleFamily == "backend engineer")

    application.setSeniorityOverride(.staff)

    #expect(application.seniorityOverride == .staff)
    #expect(application.effectiveSeniority == .staff)
}

@Test func marketSalaryBenchmarkUsesTieredFallbackAndPercentiles() async {
    let current = JobApplication(
        companyName: "Current",
        role: "Senior Backend Engineer",
        location: "Remote",
        currency: .usd,
        expectedSalaryMin: 200_000,
        expectedSalaryMax: 220_000
    )

    let peerA = JobApplication(
        companyName: "A",
        role: "Senior Backend Engineer",
        location: "New York",
        currency: .usd,
        expectedSalaryMin: 210_000,
        expectedSalaryMax: 210_000
    )
    let peerB = JobApplication(
        companyName: "B",
        role: "Senior Backend Engineer",
        location: "San Francisco",
        currency: .usd,
        expectedSalaryMin: 220_000,
        expectedSalaryMax: 220_000
    )
    let peerC = JobApplication(
        companyName: "C",
        role: "Senior Backend Engineer",
        location: "Austin",
        currency: .usd,
        expectedSalaryMin: 230_000,
        expectedSalaryMax: 230_000
    )

    let snapshotA = CompanySalarySnapshot(
        roleTitle: "Senior Backend Engineer",
        location: "London",
        sourceName: "Levels.fyi",
        currency: .usd,
        minTotalCompensation: 240_000,
        maxTotalCompensation: 240_000
    )
    let snapshotB = CompanySalarySnapshot(
        roleTitle: "Senior Backend Engineer",
        location: "Remote",
        sourceName: "Glassdoor",
        currency: .usd,
        minTotalCompensation: 250_000,
        maxTotalCompensation: 250_000
    )

    let service = MarketSalaryBenchmarkService(exchangeRateService: FixedSalaryExchangeRateProvider(rate: 1.0))
    let result = await service.benchmark(
        for: current,
        among: [current, peerA, peerB, peerC],
        salarySnapshots: [snapshotA, snapshotB],
        baseCurrency: .usd
    )

    #expect(result != nil)
    #expect(result?.matchTier == .exactRoleAnyLocation)
    #expect(result?.percentile25 == 220_000)
    #expect(result?.percentile50 == 230_000)
    #expect(result?.percentile75 == 240_000)
    #expect(result?.cohortCount == 5)
    #expect(result?.internalApplicationCount == 3)
    #expect(result?.externalSnapshotCount == 2)
}

@Test func personalSalaryAnalyticsComputesClusterAndAskOfferDelta() async {
    let applications = (0..<10).map { index in
        JobApplication(
            companyName: "Example \(index)",
            role: "Engineer",
            location: "Remote",
            currency: .usd,
            expectedSalaryMin: 100_000 + (index * 10_000),
            expectedSalaryMax: 100_000 + (index * 10_000),
            offerBaseCompensation: index < 3 ? 110_000 + (index * 10_000) : nil,
            updatedAt: Date()
        )
    }

    let service = PersonalSalaryAnalyticsService(exchangeRateService: FixedSalaryExchangeRateProvider(rate: 1.0))
    let result = await service.analyze(applications: applications, baseCurrency: .usd)

    #expect(result != nil)
    #expect(result?.expectedDataPointCount == 10)
    #expect(result?.expectedClusterMin == 120_000)
    #expect(result?.expectedClusterMax == 170_000)
    #expect(result?.askOfferOverlapCount == 3)
    #expect(result?.averageOfferDeltaPercent.map { Int($0.rounded()) } == 9)
    #expect(result?.summaryText?.contains("clusters around") == true)
}

@Test func companyResearchParsesSalaryFindingSeniority() throws {
    let result = try CompanyResearchService.parseResponse(
        """
        {
          "summary": "Example summary",
          "salaryFindings": [
            {
              "roleTitle": "Staff Engineer",
              "location": "San Francisco",
              "sourceName": "LinkedIn Salary",
              "currency": "USD",
              "seniority": "staff",
              "minTotalCompensation": 310000,
              "maxTotalCompensation": 360000
            }
          ]
        }
        """,
        usage: nil,
        sourcePayloads: []
    )

    #expect(result.salaryFindings.count == 1)
    #expect(result.salaryFindings.first?.seniority == .staff)
    #expect(result.salaryFindings.first?.sourceName == "LinkedIn Salary")
}

@Test func applicationNegotiationGuidanceRejectsUnsupportedModels() {
    #expect(ApplicationNegotiationGuidanceService.isSupported(provider: .openAI, model: "") == false)
}

@Test func applicationNegotiationGuidanceUsesBenchmarkAndReturnsCounterRange() async throws {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "Senior Engineer",
        location: "San Francisco",
        status: .offered,
        currency: .usd,
        offerBaseCompensation: 250_000
    )

    let benchmark = MarketSalaryBenchmarkResult(
        baseCurrency: .usd,
        comparisonBasis: .offer,
        matchTier: .exactRoleLocation,
        confidence: .high,
        seniority: .senior,
        cohortCount: 8,
        internalApplicationCount: 4,
        externalSnapshotCount: 4,
        sourceCounts: [MarketSalarySourceCount(sourceName: "Pipeline", count: 4)],
        percentile25: 240_000,
        percentile50: 270_000,
        percentile75: 300_000,
        currentCompensation: 250_000,
        deltaFromMedian: -20_000,
        deltaPercentFromMedian: -7.4,
        comparisonText: "Your current compensation is 7% below median.",
        missingConversionCount: 0,
        lastRefreshedAt: Date()
    )

    let output = try await ApplicationNegotiationGuidanceService.generate(
        provider: .openAI,
        apiKey: "test",
        model: "gpt-5-mini",
        application: application,
        benchmark: benchmark,
        savedSnapshots: [],
        researchProvider: StubNegotiationResearchProvider(),
        completionProvider: StubNegotiationCompletionProvider()
    )

    #expect(output.suggestedCounterMin == 270_000)
    #expect(output.suggestedCounterMax == 300_000)
    #expect(output.text.contains("counter") == true)
    #expect(output.citations.count == 1)
}

private struct FixedSalaryExchangeRateProvider: ExchangeRateProviding {
    let rate: Double

    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult? {
        if from == to {
            return ExchangeRateService.ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }
        return ExchangeRateService.ConversionResult(amount: Double(amount) * rate, rateDate: date, usedFallback: false)
    }
}

private struct StubNegotiationResearchProvider: ApplicationNegotiationResearchProviding {
    func groundedWebSearch(
        provider _: AIProvider,
        apiKey _: String,
        model _: String,
        query _: String,
        systemPrompt _: String?,
        domains _: [String],
        maxTokens _: Int
    ) async throws -> AIWebSearchResponse {
        AIWebSearchResponse(
            text: "Median compensation appears to be above the current offer.",
            citations: [
                AIWebSearchCitation(
                    title: "Levels.fyi sample",
                    urlString: "https://www.levels.fyi/example"
                )
            ]
        )
    }
}

private struct StubNegotiationCompletionProvider: ApplicationNegotiationCompletionProviding {
    func complete(
        provider _: AIProvider,
        apiKey _: String,
        model _: String,
        systemPrompt _: String,
        userPrompt _: String,
        maxTokens _: Int,
        temperature _: Double
    ) async throws -> AICompletionResponse {
        AICompletionResponse(text: "You have room to counter. Ask for a market-aligned counter range.")
    }
}
