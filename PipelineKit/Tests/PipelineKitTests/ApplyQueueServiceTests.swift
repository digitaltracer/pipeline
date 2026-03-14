import Foundation
import Testing
@testable import PipelineKit

@Test func applyQueueRanksFreshScoresBeforeDeadlinesAndUsesDeadlineOrderForUnscoredJobs() {
    let preferences = JobMatchPreferences()
    let currentResumeRevisionID = UUID()
    let queueService = ApplyQueueService()

    let topScored = makeQueuedApplication(
        companyName: "Alpha",
        role: "iOS Engineer",
        createdAt: makeApplyQueueDate("2026-03-01T09:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-01T10:00:00Z"),
        postedAt: makeApplyQueueDate("2026-02-20T09:00:00Z"),
        deadline: makeApplyQueueDate("2026-03-20T09:00:00Z"),
        jobDescription: "Ship SwiftUI features."
    )
    topScored.matchAssessment = makeFreshAssessment(
        score: 91,
        application: topScored,
        resumeRevisionID: currentResumeRevisionID,
        preferences: preferences
    )

    let lowerScored = makeQueuedApplication(
        companyName: "Beta",
        role: "Platform Engineer",
        createdAt: makeApplyQueueDate("2026-03-01T11:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-01T12:00:00Z"),
        postedAt: makeApplyQueueDate("2026-02-15T09:00:00Z"),
        deadline: makeApplyQueueDate("2026-03-10T09:00:00Z"),
        jobDescription: "Build internal tooling."
    )
    lowerScored.matchAssessment = makeFreshAssessment(
        score: 78,
        application: lowerScored,
        resumeRevisionID: currentResumeRevisionID,
        preferences: preferences
    )

    let staleScore = makeQueuedApplication(
        companyName: "Gamma",
        role: "App Engineer",
        createdAt: makeApplyQueueDate("2026-03-02T09:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-02T10:00:00Z"),
        postedAt: makeApplyQueueDate("2026-02-10T09:00:00Z"),
        deadline: makeApplyQueueDate("2026-03-05T09:00:00Z"),
        jobDescription: "Own app performance."
    )
    staleScore.matchAssessment = makeFreshAssessment(
        score: 88,
        application: staleScore,
        resumeRevisionID: UUID(),
        preferences: preferences
    )

    let unscored = makeQueuedApplication(
        companyName: "Delta",
        role: "Frontend Engineer",
        createdAt: makeApplyQueueDate("2026-03-02T11:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-02T12:00:00Z"),
        postedAt: makeApplyQueueDate("2026-02-12T09:00:00Z"),
        deadline: makeApplyQueueDate("2026-03-08T09:00:00Z"),
        jobDescription: "Build product surfaces."
    )

    let snapshot = queueService.snapshot(
        from: [unscored, staleScore, lowerScored, topScored],
        dailyTarget: 10,
        currentResumeRevisionID: currentResumeRevisionID,
        matchPreferences: preferences
    )

    #expect(snapshot.todayQueue.map(\.application.companyName) == ["Alpha", "Beta", "Gamma", "Delta"])
    #expect(snapshot.todayQueue[0].freshMatchScore == 91)
    #expect(snapshot.todayQueue[2].freshMatchScore == nil)
    #expect(snapshot.todayQueue[2].isMatchScoreStale)
}

@Test func applyQueueEstimateAddsMissingPreparationWork() {
    let queueService = ApplyQueueService()
    let application = makeQueuedApplication(
        companyName: "OpenAI",
        role: "Designer",
        createdAt: makeApplyQueueDate("2026-03-03T09:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-03T09:30:00Z"),
        postedAt: nil,
        deadline: nil,
        jobDescription: "Create polished product experiences."
    )

    let snapshot = queueService.snapshot(
        from: [application],
        dailyTarget: 4,
        currentResumeRevisionID: nil,
        matchPreferences: JobMatchPreferences()
    )

    #expect(snapshot.todayQueue.count == 1)
    #expect(snapshot.todayQueue[0].estimatedMinutes == 90)
    #expect(snapshot.totalEstimatedMinutes == 90)
}

@Test func savedPreparationStatusRequiresResumeCoverLetterAndSuccessfulResearch() {
    let company = CompanyProfile(name: "OpenAI")
    let application = makeQueuedApplication(
        companyName: "OpenAI",
        role: "Staff Engineer",
        createdAt: makeApplyQueueDate("2026-03-04T09:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-04T09:15:00Z"),
        postedAt: nil,
        deadline: nil,
        jobDescription: "Own product quality."
    )
    application.company = company

    let resumeSnapshot = ResumeJobSnapshot(rawJSON: #"{"name":"Candidate"}"#)
    resumeSnapshot.application = application
    application.resumeSnapshots = [resumeSnapshot]

    let coverLetter = CoverLetterDraft(plainText: "Dear hiring team,", application: application)
    application.assignCoverLetterDraft(coverLetter)

    let failedResearch = CompanyResearchSnapshot(
        providerID: "openai",
        model: "gpt-test",
        requestStatus: .failed,
        runStatus: .failed,
        summaryText: nil
    )
    failedResearch.company = company
    company.researchSnapshots = [failedResearch]

    let failedStatus = SavedApplicationPreparationService.status(for: application)
    #expect(failedStatus.isReadyToApply == false)
    #expect(failedStatus.missingPreparationTitles == ["Company research"])

    let successfulResearch = CompanyResearchSnapshot(
        providerID: "openai",
        model: "gpt-test",
        requestStatus: .succeeded,
        runStatus: .succeeded,
        summaryText: "Healthy growth."
    )
    successfulResearch.company = company
    company.researchSnapshots = [failedResearch, successfulResearch]

    let readyStatus = SavedApplicationPreparationService.status(for: application)
    #expect(readyStatus.isReadyToApply)
    #expect(readyStatus.missingPreparationTitles.isEmpty)
}

@Test func leavingSavedStatusClearsApplyQueueMembership() {
    let application = makeQueuedApplication(
        companyName: "Example",
        role: "Engineer",
        createdAt: makeApplyQueueDate("2026-03-05T09:00:00Z"),
        queuedAt: makeApplyQueueDate("2026-03-05T09:30:00Z"),
        postedAt: nil,
        deadline: nil,
        jobDescription: "Build systems."
    )

    #expect(application.isInApplyQueue)
    #expect(application.queuedAt != nil)

    application.status = .applied

    #expect(application.isInApplyQueue == false)
    #expect(application.queuedAt == nil)
}

private func makeQueuedApplication(
    companyName: String,
    role: String,
    createdAt: Date,
    queuedAt: Date?,
    postedAt: Date?,
    deadline: Date?,
    jobDescription: String
) -> JobApplication {
    JobApplication(
        companyName: companyName,
        role: role,
        location: "Remote",
        jobDescription: jobDescription,
        status: .saved,
        isInApplyQueue: true,
        queuedAt: queuedAt,
        postedAt: postedAt,
        applicationDeadline: deadline,
        createdAt: createdAt,
        updatedAt: createdAt
    )
}

private func makeFreshAssessment(
    score: Int,
    application: JobApplication,
    resumeRevisionID: UUID,
    preferences: JobMatchPreferences
) -> JobMatchAssessment {
    let assessment = JobMatchAssessment()
    assessment.applyReadyState(
        overallScore: score,
        skillsScore: score,
        experienceScore: score,
        salaryScore: nil,
        locationScore: nil,
        matchedSkills: ["Swift"],
        missingSkills: [],
        summary: "Strong fit",
        gapAnalysis: nil,
        resumeRevisionID: resumeRevisionID,
        jobDescriptionHash: JobMatchScoringService.jobDescriptionHash(for: application),
        preferencesFingerprint: preferences.fingerprint,
        scoringVersion: JobMatchScoringService.scoringVersion,
        scoredAt: makeApplyQueueDate("2026-03-06T09:00:00Z")
    )
    assessment.application = application
    return assessment
}

private func makeApplyQueueDate(_ rawValue: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: rawValue)!
}
