import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func companyLinkingBackfillsSharedProfilesByNormalizedName() throws {
    let container = try makeCompanyContainer()
    let context = ModelContext(container)

    let first = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "San Francisco"
    )
    let second = JobApplication(
        companyName: "OpenAI, Inc.",
        role: "Platform Engineer",
        location: "Remote"
    )

    context.insert(first)
    context.insert(second)
    try context.save()

    let linkedCount = try CompanyLinkingService.backfillApplicationsIfNeeded(in: context)
    let companies = try context.fetch(FetchDescriptor<CompanyProfile>())

    #expect(linkedCount == 2)
    #expect(companies.count == 1)
    #expect(first.company?.id == second.company?.id)
    #expect(first.companyName == "OpenAI")
    #expect(second.companyName == "OpenAI, Inc.")
}

@Test func companyResearchApplyPersistsSourcesAndSalarySnapshots() throws {
    let container = try makeCompanyContainer()
    let context = ModelContext(container)

    let company = CompanyProfile(
        name: "Anthropic",
        userRating: 5,
        notesMarkdown: "Manual notes should stay untouched."
    )
    context.insert(company)
    try context.save()

    let result = CompanyResearchResult(
        websiteURL: "https://anthropic.com",
        linkedInURL: nil,
        glassdoorURL: nil,
        levelsFYIURL: nil,
        teamBlindURL: nil,
        industry: "AI Research",
        sizeBand: .enterprise,
        headquarters: "San Francisco, CA",
        summary: "Anthropic builds frontier AI systems with a strong safety focus.",
        sources: [
            CompanyResearchSourcePayload(
                title: "Company Website",
                urlString: "https://anthropic.com",
                sourceKind: .companyWebsite,
                fetchStatus: .fetched,
                contentExcerpt: "Anthropic builds reliable AI systems.",
                fetchedText: "Anthropic builds reliable AI systems.",
                errorMessage: nil,
                orderIndex: 0
            ),
            CompanyResearchSourcePayload(
                title: "Glassdoor Search",
                urlString: "https://www.google.com/search?q=anthropic+glassdoor",
                sourceKind: .search,
                fetchStatus: .failed,
                contentExcerpt: nil,
                fetchedText: nil,
                errorMessage: "Blocked",
                orderIndex: 1
            )
        ],
        salaryFindings: [
            CompanyResearchSalaryFinding(
                roleTitle: "Research Engineer",
                location: "San Francisco",
                sourceName: "Levels.fyi",
                sourceURLString: "https://www.levels.fyi",
                notes: "Estimated band",
                confidenceNotes: "Best-effort estimate",
                currency: .usd,
                seniority: .staff,
                minBaseCompensation: 220_000,
                maxBaseCompensation: 260_000,
                minTotalCompensation: 260_000,
                maxTotalCompensation: 340_000
            )
        ],
        usage: AIUsageMetrics(promptTokens: 100, completionTokens: 50, totalTokens: 150),
        rawResponseText: "{\"summary\":\"Anthropic...\"}"
    )

    let snapshot = try CompanyResearchService.applyResearchResult(
        result,
        to: company,
        provider: .openAI,
        model: "gpt-5-mini",
        applicationID: nil,
        requestStatus: .succeeded,
        startedAt: Date(timeIntervalSinceReferenceDate: 100),
        finishedAt: Date(timeIntervalSinceReferenceDate: 120),
        in: context
    )

    #expect(snapshot.requestStatus == AIUsageRequestStatus.succeeded)
    #expect(company.notesMarkdown == "Manual notes should stay untouched.")
    #expect(company.lastResearchSummary?.contains("Anthropic builds frontier AI systems") == true)
    #expect(company.industry == "AI Research")
    #expect(company.sizeBand == CompanySizeBand.enterprise)
    #expect(company.sortedResearchSources.count == 2)
    #expect(company.sortedSalarySnapshots.count == 1)
    #expect(company.sortedSalarySnapshots.first?.sourceName == "Levels.fyi")
    #expect(company.sortedSalarySnapshots.first?.seniority == .staff)
}

@Test func companyResearchValidationRejectsSearchInterstitialPages() {
    let company = CompanyProfile(name: "Moloco")
    let validation = CompanyResearchService.validateEvidence(
        text: CompanyResearchService.normalizeEvidenceText(
            "Google Search Please click here if you are not redirected within a few seconds. Send feedback."
        ),
        company: company,
        sourceKind: .search,
        requestedURLString: "https://www.google.com/search?q=moloco",
        resolvedURLString: "https://www.google.com/search?q=moloco",
        acquisitionMethod: .urlSession,
        fallbackTitle: "Company Search"
    )

    #expect(validation.validationStatus == .invalid)
    #expect(validation.fetchStatus == .invalid)
}

@Test func companyResearchValidationMarksLinkedInLoginWallsBlocked() {
    let company = CompanyProfile(name: "Moloco")
    let validation = CompanyResearchService.validateEvidence(
        text: CompanyResearchService.normalizeEvidenceText(
            "Join LinkedIn Sign in to view more about Moloco and open jobs."
        ),
        company: company,
        sourceKind: .linkedIn,
        requestedURLString: "https://www.linkedin.com/company/moloco",
        resolvedURLString: "https://www.linkedin.com/company/moloco",
        acquisitionMethod: .urlSession,
        fallbackTitle: "LinkedIn"
    )

    #expect(validation.validationStatus == .blocked)
    #expect(validation.fetchStatus == .blocked)
}

@Test func companyResearchRunStatusReturnsPartialForMixedEvidence() {
    let runStatus = CompanyResearchService.runStatus(
        for: [
            CompanyResearchSourcePayload(
                title: "Company Website",
                urlString: "https://moloco.com",
                sourceKind: .companyWebsite,
                fetchStatus: .verified,
                contentExcerpt: "Moloco builds machine learning advertising products.",
                fetchedText: "Moloco builds machine learning advertising products for app marketers.",
                errorMessage: nil,
                orderIndex: 0,
                resolvedURLString: "https://moloco.com",
                validationStatus: .verified,
                acquisitionMethod: .urlSession,
                validationReason: "Validated company-specific evidence.",
                confidence: .high
            ),
            CompanyResearchSourcePayload(
                title: "LinkedIn",
                urlString: "https://www.linkedin.com/company/moloco",
                sourceKind: .linkedIn,
                fetchStatus: .blocked,
                contentExcerpt: nil,
                fetchedText: nil,
                errorMessage: "HTTP 999",
                orderIndex: 1,
                resolvedURLString: nil,
                validationStatus: .blocked,
                acquisitionMethod: .urlSession,
                validationReason: "The source appears blocked, gated, or anti-bot protected.",
                confidence: .low
            )
        ],
        summary: "Moloco is an ad-tech company focused on machine learning."
    )

    #expect(runStatus == .partial)
}

@Test func companyResearchRunStatusFailsWithoutVerifiedEvidence() {
    let runStatus = CompanyResearchService.runStatus(
        for: [
            CompanyResearchSourcePayload(
                title: "Company Search",
                urlString: "https://www.google.com/search?q=moloco",
                sourceKind: .search,
                fetchStatus: .invalid,
                contentExcerpt: nil,
                fetchedText: nil,
                errorMessage: "Search interstitial",
                orderIndex: 0,
                resolvedURLString: nil,
                validationStatus: .invalid,
                acquisitionMethod: .urlSession,
                validationReason: "Search results or redirect page, not a usable source page.",
                confidence: .low
            )
        ],
        summary: nil
    )

    #expect(runStatus == .failed)
}

@Test func companyCompensationComparisonIncludesInternalAndExternalRows() async throws {
    let company = CompanyProfile(name: "Stripe")
    let current = JobApplication(
        companyName: "Stripe",
        role: "Backend Engineer",
        location: "Remote",
        currency: .usd,
        expectedSalaryMin: 180_000,
        expectedSalaryMax: 220_000,
        company: company
    )
    let peer = JobApplication(
        companyName: "Stripe",
        role: "Senior Backend Engineer",
        location: "New York",
        currency: .usd,
        expectedSalaryMin: 210_000,
        expectedSalaryMax: 250_000,
        company: company
    )
    let external = CompanySalarySnapshot(
        roleTitle: "Backend Engineer",
        location: "Remote",
        sourceName: "Glassdoor",
        currency: .eur,
        minBaseCompensation: 150_000,
        maxBaseCompensation: 190_000,
        company: company
    )

    company.applications = [current, peer]
    company.salarySnapshots = [external]

    let service = CompanyCompensationComparisonService(
        exchangeRateService: FixedExchangeRateProvider(rate: 1.2)
    )

    let comparison = await service.makeComparison(
        for: current,
        company: company,
        baseCurrency: .usd
    )

    #expect(comparison.internalRows.count == 1)
    #expect(comparison.externalRows.count == 1)
    #expect(comparison.currentApplicationRangeText?.contains("$180") == true)
    #expect(comparison.externalRows.first?.rangeText.contains("$180") == true)
}

private func makeCompanyContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        JobSearchCycle.self,
        SearchGoal.self,
        InterviewLog.self,
        CompanyProfile.self,
        CompanyResearchSnapshot.self,
        CompanyResearchSource.self,
        CompanySalarySnapshot.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self,
        InterviewDebrief.self,
        RejectionLog.self,
        InterviewQuestionEntry.self,
        InterviewLearningSnapshot.self,
        RejectionLearningSnapshot.self,
        ApplicationTask.self,
        FollowUpStep.self,
        ApplicationChecklistSuggestion.self,
        ApplicationAttachment.self,
        CoverLetterDraft.self,
        ATSCompatibilityAssessment.self,
        ATSCompatibilityScanRun.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        AIUsageRecord.self,
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private struct FixedExchangeRateProvider: ExchangeRateProviding {
    let rate: Double

    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult? {
        if from == to {
            return ExchangeRateService.ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }
        return ExchangeRateService.ConversionResult(amount: Double(amount) * rate, rateDate: date, usedFallback: false)
    }
}
