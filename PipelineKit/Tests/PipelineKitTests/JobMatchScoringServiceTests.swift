import Foundation
import Testing
@testable import PipelineKit

@Test func jobMatchBlockedDraftSignalsMissingMasterResume() {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote",
        jobDescription: "Build SwiftUI features."
    )

    let draft = JobMatchScoringService.blockedDraft(
        reason: .missingMasterResume,
        application: application,
        preferences: JobMatchPreferences()
    )

    #expect(draft.status == .blocked)
    #expect(draft.blockedReason == .missingMasterResume)
    #expect(draft.overallScore == nil)
}

@Test func jobMatchBlockedDraftSignalsMissingJobDescription() {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote"
    )

    let draft = JobMatchScoringService.blockedDraft(
        reason: .missingJobDescription,
        application: application,
        preferences: JobMatchPreferences()
    )

    #expect(draft.status == .blocked)
    #expect(draft.blockedReason == .missingJobDescription)
    #expect(draft.jobDescriptionHash == nil)
}

@Test func jobMatchParserAcceptsValidJSON() throws {
    let payload = """
    {
      "skillsScore": 84,
      "experienceScore": 76,
      "matchedSkills": ["SwiftUI", "Swift"],
      "missingSkills": ["Kubernetes"],
      "summary": "Strong iOS alignment.",
      "gapAnalysis": "The role asks for Kubernetes exposure."
    }
    """

    let result = try JobMatchScoringService.parseAIAnalysis(from: payload, usage: nil)
    #expect(result.skillsScore == 84)
    #expect(result.experienceScore == 76)
    #expect(result.matchedSkills == ["SwiftUI", "Swift"])
    #expect(result.missingSkills == ["Kubernetes"])
}

@Test func jobMatchParserRejectsMalformedJSON() {
    do {
        _ = try JobMatchScoringService.parseAIAnalysis(from: "not-json", usage: nil)
        Issue.record("Expected parseAIAnalysis to fail for malformed JSON.")
    } catch let error as AIServiceError {
        switch error {
        case .parsingError(let message):
            #expect(message.contains("not valid JSON"))
        default:
            Issue.record("Expected parsingError, got \(error)")
        }
    } catch {
        Issue.record("Expected AIServiceError, got \(error)")
    }
}

@Test func salaryScoreIsPerfectWhenPostedCompMeetsTarget() {
    let score = JobMatchScoringService.computeSalaryScore(
        postedMaximumCompensationInPreferenceCurrency: 210_000,
        targetMinimumCompensationInPreferenceCurrency: 200_000
    )

    #expect(score == 100)
}

@Test func salaryScoreScalesWhenPostedCompIsBelowTarget() {
    let score = JobMatchScoringService.computeSalaryScore(
        postedMaximumCompensationInPreferenceCurrency: 150_000,
        targetMinimumCompensationInPreferenceCurrency: 200_000
    )

    #expect(score == 75)
}

@Test func salaryScoreReturnsNilWhenInputsAreMissing() {
    let score = JobMatchScoringService.computeSalaryScore(
        postedMaximumCompensationInPreferenceCurrency: nil,
        targetMinimumCompensationInPreferenceCurrency: 200_000
    )

    #expect(score == nil)
}

@Test func locationScoreRecognizesRemoteMatch() {
    let application = JobApplication(
        companyName: "Example",
        role: "Engineer",
        location: "Remote - United States"
    )
    let preferences = JobMatchPreferences(
        allowedWorkModes: [.remote],
        preferredLocations: []
    )

    let score = JobMatchScoringService.computeLocationScore(application: application, preferences: preferences)
    #expect(score == 100)
}

@Test func locationScoreRejectsOnSiteLocationMismatch() {
    let application = JobApplication(
        companyName: "Example",
        role: "Engineer",
        location: "New York, NY (On-site)"
    )
    let preferences = JobMatchPreferences(
        allowedWorkModes: [.onSite],
        preferredLocations: ["San Francisco"]
    )

    let score = JobMatchScoringService.computeLocationScore(application: application, preferences: preferences)
    #expect(score == 0)
}

@Test func overallScoreRenormalizesWhenOptionalDimensionsAreUnavailable() {
    let score = JobMatchScoringService.computeOverallScore(
        skillsScore: 80,
        experienceScore: 60,
        salaryScore: nil,
        locationScore: nil
    )

    #expect(score == 74)
}

@Test func staleDetectionRespondsToResumePreferencesAndDescriptionChanges() {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "Engineer",
        location: "Remote",
        jobDescription: "Build product features."
    )
    let preferences = JobMatchPreferences(preferredCurrency: .usd, preferredSalaryMin: 180_000, allowedWorkModes: [.remote])
    let assessment = JobMatchAssessment(
        overallScore: 82,
        skillsScore: 85,
        experienceScore: 75,
        status: .ready,
        resumeRevisionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
        jobDescriptionHash: JobMatchScoringService.jobDescriptionHash(for: application),
        preferencesFingerprint: preferences.fingerprint,
        scoringVersion: JobMatchScoringService.scoringVersion,
        scoredAt: Date()
    )
    application.matchAssessment = assessment
    assessment.application = application

    #expect(
        JobMatchScoringService.isStale(
            assessment,
            application: application,
            currentResumeRevisionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
            preferences: preferences
        ) == false
    )

    let changedPreferences = JobMatchPreferences(preferredCurrency: .usd, preferredSalaryMin: 200_000, allowedWorkModes: [.remote])
    #expect(
        JobMatchScoringService.isStale(
            assessment,
            application: application,
            currentResumeRevisionID: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"),
            preferences: changedPreferences
        ) == true
    )
}

@Test func dashboardAnalyticsAverageMatchScoreExcludesStaleAssessments() async {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "Engineer",
        location: "Remote",
        jobDescription: "Build product features.",
        appliedDate: makeDate("2026-03-03"),
        updatedAt: makeDate("2026-03-03")
    )
    let staleApplication = JobApplication(
        companyName: "Example",
        role: "Engineer",
        location: "Remote",
        jobDescription: "Ship APIs.",
        appliedDate: makeDate("2026-03-04"),
        updatedAt: makeDate("2026-03-04")
    )
    let currentResumeID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")
    let oldResumeID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
    let preferences = JobMatchPreferences(preferredCurrency: .usd, preferredSalaryMin: 180_000, allowedWorkModes: [.remote])

    let freshAssessment = JobMatchAssessment(
        overallScore: 80,
        skillsScore: 82,
        experienceScore: 78,
        status: .ready,
        resumeRevisionID: currentResumeID,
        jobDescriptionHash: JobMatchScoringService.jobDescriptionHash(for: application),
        preferencesFingerprint: preferences.fingerprint,
        scoringVersion: JobMatchScoringService.scoringVersion,
        scoredAt: Date()
    )
    freshAssessment.application = application
    application.matchAssessment = freshAssessment

    let staleAssessment = JobMatchAssessment(
        overallScore: 20,
        skillsScore: 30,
        experienceScore: 25,
        status: .ready,
        resumeRevisionID: oldResumeID,
        jobDescriptionHash: JobMatchScoringService.jobDescriptionHash(for: staleApplication),
        preferencesFingerprint: preferences.fingerprint,
        scoringVersion: JobMatchScoringService.scoringVersion,
        scoredAt: Date()
    )
    staleAssessment.application = staleApplication
    staleApplication.matchAssessment = staleAssessment

    let analytics = await DashboardAnalyticsService(exchangeRateService: LocalMockExchangeRateProvider(rate: 1.0)).analyze(
        applications: [application, staleApplication],
        cycles: [],
        goals: [],
        scope: .thisMonth,
        baseCurrency: .usd,
        currentResumeRevisionID: currentResumeID,
        matchPreferences: preferences,
        referenceDate: makeDate("2026-03-08")
    )

    #expect(analytics.averageMatchScore == 80)
    #expect(analytics.staleMatchCount == 1)
}

private func makeDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value) ?? Date()
}

private struct LocalMockExchangeRateProvider: ExchangeRateProviding {
    let rate: Double

    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult? {
        ExchangeRateService.ConversionResult(amount: Double(amount) * rate, rateDate: date, usedFallback: false)
    }
}
