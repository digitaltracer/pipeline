import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func cycleMigrationBackfillsImportedSearchAndAssignsApplications() throws {
    let container = try makeAnalyticsContainer()
    let context = ModelContext(container)

    let first = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "San Francisco"
    )
    let second = JobApplication(
        companyName: "Stripe",
        role: "Staff Engineer",
        location: "Remote",
        status: .interviewing
    )

    context.insert(first)
    context.insert(second)
    try context.save()

    let importedCycle = try JobSearchCycleMigrationService.backfillImportedCycleIfNeeded(in: context)
    let cycles = try context.fetch(FetchDescriptor<JobSearchCycle>())

    #expect(importedCycle?.name == "Imported Search")
    #expect(cycles.count == 1)
    #expect(first.cycle?.id == importedCycle?.id)
    #expect(second.cycle?.id == importedCycle?.id)
    #expect(importedCycle?.isActive == true)
}

@Test func dashboardAnalyticsComputesCycleComparisonAndGoalProgress() async throws {
    let previousCycle = JobSearchCycle(
        name: "Winter Search",
        startDate: Calendar.current.date(byAdding: .month, value: -2, to: Date()) ?? Date(),
        endDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()),
        isActive: false
    )
    let activeCycle = JobSearchCycle(
        name: "Spring Search",
        startDate: Calendar.current.date(byAdding: .day, value: -10, to: Date()) ?? Date(),
        isActive: true
    )

    let submittedDate = Calendar.current.date(
        byAdding: .day,
        value: 1,
        to: Calendar.current.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    ) ?? Date()

    let activeApplication = JobApplication(
        companyName: "Anthropic",
        role: "Engineer",
        location: "Remote",
        status: .offered,
        salaryMin: 180_000,
        salaryMax: 220_000,
        expectedSalaryMin: 200_000,
        expectedSalaryMax: 230_000,
        offerBaseCompensation: 240_000,
        appliedDate: submittedDate,
        cycle: activeCycle,
        updatedAt: submittedDate
    )
    let log = InterviewLog(
        interviewType: .finalRound,
        date: submittedDate,
        application: activeApplication
    )
    activeApplication.addInterviewLog(log)

    let previousApplication = JobApplication(
        companyName: "Apple",
        role: "Engineer",
        location: "Cupertino",
        status: .applied,
        appliedDate: Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date(),
        cycle: previousCycle
    )

    let weeklyGoal = SearchGoal(
        metric: .applicationsSubmitted,
        cadence: .weekly,
        targetValue: 3,
        cycle: activeCycle
    )

    let analyticsService = DashboardAnalyticsService(exchangeRateService: MockExchangeRateProvider(rate: 1.0))
    let analytics = await analyticsService.analyze(
        applications: [activeApplication, previousApplication],
        cycles: [previousCycle, activeCycle],
        goals: [weeklyGoal],
        scope: .currentCycle,
        baseCurrency: .usd
    )

    #expect(analytics.currentSnapshot.totalApplications == 1)
    #expect(analytics.previousSnapshot.totalApplications == 1)
    #expect(analytics.currentSnapshot.offeredApplications == 1)
    #expect(analytics.goalProgress.count == 1)
    #expect(analytics.goalProgress.first?.progress == 1)
    #expect(analytics.activeCycle?.name == "Spring Search")
    #expect(analytics.previousCycle?.name == "Winter Search")
}

@Test func dashboardAnalyticsConvertsCompensationIntoBaseCurrency() async {
    let application = JobApplication(
        companyName: "Example",
        role: "Engineer",
        location: "Remote",
        currency: .inr,
        salaryMin: 10_000_000,
        salaryMax: 12_000_000,
        expectedSalaryMin: 11_000_000,
        expectedSalaryMax: 13_000_000,
        offerBaseCompensation: 14_000_000,
        appliedDate: Date(),
        updatedAt: Date()
    )

    let analyticsService = DashboardAnalyticsService(exchangeRateService: MockExchangeRateProvider(rate: 0.01))
    let analytics = await analyticsService.analyze(
        applications: [application],
        cycles: [],
        goals: [],
        scope: .thisMonth,
        baseCurrency: .usd
    )

    #expect(analytics.salaryDistribution.isEmpty == false)
    #expect(analytics.averageExpectedComp == 120_000)
    #expect(analytics.averageOfferedComp == 140_000)
}

@Test func dashboardAnalyticsComputesChecklistPerformance() async {
    let currentApplication = JobApplication(
        companyName: "OpenAI",
        role: "Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeDate("2026-03-03"),
        updatedAt: makeDate("2026-03-03")
    )
    let completedChecklist = ApplicationTask(
        title: "Tailor resume",
        isCompleted: true,
        completedAt: makeDate("2026-03-04"),
        application: currentApplication,
        origin: .smartChecklist,
        checklistTemplateID: "tailorResume"
    )
    let overdueChecklist = ApplicationTask(
        title: "Follow up",
        dueDate: makeDate("2026-03-01"),
        application: currentApplication,
        origin: .smartChecklist,
        checklistTemplateID: "followUpOnApplication"
    )
    currentApplication.tasks = [completedChecklist, overdueChecklist]

    let previousApplication = JobApplication(
        companyName: "Anthropic",
        role: "Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeDate("2026-02-10"),
        updatedAt: makeDate("2026-02-10")
    )
    let previousChecklist = ApplicationTask(
        title: "Research company",
        application: previousApplication,
        origin: .smartChecklist,
        checklistTemplateID: "researchCompany"
    )
    previousApplication.tasks = [previousChecklist]

    let analyticsService = DashboardAnalyticsService(exchangeRateService: MockExchangeRateProvider(rate: 1.0))
    let analytics = await analyticsService.analyze(
        applications: [currentApplication, previousApplication],
        cycles: [],
        goals: [],
        scope: .thisMonth,
        baseCurrency: .usd,
        referenceDate: makeDate("2026-03-08")
    )

    #expect(analytics.currentChecklist.totalItems == 2)
    #expect(analytics.currentChecklist.completedItems == 1)
    #expect(analytics.currentChecklist.openItems == 1)
    #expect(analytics.currentChecklist.overdueItems == 1)
    #expect(analytics.currentChecklist.completionRate == 0.5)
    #expect(analytics.previousChecklist.totalItems == 1)
    #expect(analytics.previousChecklist.completedItems == 0)
}

@Test func dashboardAnalyticsIncludesRejectionSummaryWhenFreshSnapshotExists() async {
    let rejected = JobApplication(
        companyName: "OpenAI",
        role: "Senior Engineer",
        location: "Remote",
        status: .rejected,
        appliedDate: makeDate("2026-03-03"),
        updatedAt: makeDate("2026-03-03")
    )
    let rejectedActivity = ApplicationActivity(
        kind: .statusChange,
        occurredAt: makeDate("2026-03-05"),
        application: rejected,
        toStatus: .rejected
    )
    let rejectedLog = RejectionLog(
        stageCategory: .technical,
        reasonCategory: .experienceMismatch,
        feedbackSource: .explicit,
        feedbackText: "Wanted more infra depth.",
        activity: rejectedActivity
    )
    rejected.activities = [rejectedActivity]
    rejectedActivity.rejectionLog = rejectedLog

    let missingLog = JobApplication(
        companyName: "Anthropic",
        role: "Staff Engineer",
        location: "Remote",
        status: .rejected,
        appliedDate: makeDate("2026-03-02"),
        updatedAt: makeDate("2026-03-02")
    )

    let snapshot = RejectionLearningSnapshot(
        patternSignals: ["Technical-stage rejections are recurring."],
        targetingSignals: ["Senior titles are converting worse than mid-level roles."],
        processSignals: ["Explicit feedback is appearing in a minority of rejection logs."],
        recoverySuggestions: ["Bias similar retries toward roles with narrower scope."],
        rejectionCount: 3,
        explicitFeedbackCount: 1,
        generatedAt: makeDate("2026-03-07")
    )

    let analyticsService = DashboardAnalyticsService(exchangeRateService: MockExchangeRateProvider(rate: 1.0))
    let analytics = await analyticsService.analyze(
        applications: [rejected, missingLog],
        cycles: [],
        goals: [],
        scope: .thisMonth,
        baseCurrency: .usd,
        rejectionLearningSnapshot: snapshot,
        referenceDate: makeDate("2026-03-08")
    )

    #expect(analytics.rejectionSummary.rejectedApplications == 2)
    #expect(analytics.rejectionSummary.loggedRejections == 1)
    #expect(analytics.rejectionSummary.missingLogCount == 1)
    #expect(analytics.rejectionSummary.hasFreshInsights == true)
    #expect(analytics.rejectionSummary.topSignal == "Technical-stage rejections are recurring.")
}

@Test func exchangeRateServiceFallsBackToLatestOfflineCachedRate() async {
    let suiteName = "ExchangeRateServiceTests-\(UUID().uuidString)"
    let userDefaults = UserDefaults(suiteName: suiteName)!
    userDefaults.removePersistentDomain(forName: suiteName)
    defer { userDefaults.removePersistentDomain(forName: suiteName) }

    MockURLProtocol.handler = { request in
        let body = #"{"date":"2026-02-01","rates":{"USD":2.0}}"#
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response, Data(body.utf8))
    }

    let successConfig = URLSessionConfiguration.ephemeral
    successConfig.protocolClasses = [MockURLProtocol.self]
    let successSession = URLSession(configuration: successConfig)
    let service = ExchangeRateService(session: successSession, userDefaults: userDefaults, calendar: Calendar(identifier: .gregorian))

    let cached = await service.convert(
        amount: 100,
        from: .inr,
        to: .usd,
        on: makeDate("2026-02-01")
    )

    #expect(cached?.amount == 200)

    MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
    let failingConfig = URLSessionConfiguration.ephemeral
    failingConfig.protocolClasses = [MockURLProtocol.self]
    let failingSession = URLSession(configuration: failingConfig)
    let failingService = ExchangeRateService(session: failingSession, userDefaults: userDefaults, calendar: Calendar(identifier: .gregorian))

    let fallback = await failingService.convert(
        amount: 100,
        from: .inr,
        to: .usd,
        on: makeDate("2026-02-05")
    )

    #expect(fallback?.amount == 200)
    #expect(fallback?.usedFallback == true)

    let olderDateFallback = await failingService.convert(
        amount: 100,
        from: .inr,
        to: .usd,
        on: makeDate("2026-01-15")
    )

    #expect(olderDateFallback?.amount == 200)
    #expect(olderDateFallback?.usedFallback == true)
}

private func makeAnalyticsContainer() throws -> ModelContainer {
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

private struct MockExchangeRateProvider: ExchangeRateProviding {
    let rate: Double

    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult? {
        if from == to {
            return ExchangeRateService.ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }
        return ExchangeRateService.ConversionResult(amount: Double(amount) * rate, rateDate: date, usedFallback: false)
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func makeDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value) ?? Date()
}
