import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func weeklyDigestComputesScheduledWindowsAcrossDST() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!

    let service = WeeklyDigestService(calendar: calendar)
    let referenceDate = makeDigestDate("2026-03-11T10:00:00-07:00")
    let schedule = WeeklyDigestSchedule(weekday: 1, hour: 19, minute: 0)

    let latestInterval = service.latestCompletedInterval(asOf: referenceDate, schedule: schedule)
    let nextRun = service.nextScheduledRun(after: referenceDate, schedule: schedule)

    #expect(latestInterval.start == makeDigestDate("2026-03-01T19:00:00-08:00"))
    #expect(latestInterval.end == makeDigestDate("2026-03-08T19:00:00-07:00"))
    #expect(nextRun == makeDigestDate("2026-03-15T19:00:00-07:00"))
}

@Test func weeklyDigestCreatesSnapshotAndAvoidsDuplicates() throws {
    let container = try makeWeeklyDigestContainer()
    let context = ModelContext(container)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let service = WeeklyDigestService(calendar: calendar)
    let referenceDate = makeDigestDate("2026-03-11T12:00:00Z")
    let application = JobApplication(
        companyName: "Stripe",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing,
        appliedDate: makeDigestDate("2026-03-03T10:00:00Z"),
        nextFollowUpDate: makeDigestDate("2026-03-12T09:00:00Z")
    )
    let interview = ApplicationActivity(
        kind: .interview,
        occurredAt: makeDigestDate("2026-03-14T15:00:00Z"),
        application: application,
        interviewStage: .technicalRound1
    )
    application.activities = [interview]

    context.insert(application)
    context.insert(interview)
    try context.save()

    let firstResult = try service.generateLatestDigestIfNeeded(
        applications: [application],
        existingDigests: [],
        in: context,
        currentResumeRevisionID: nil,
        matchPreferences: JobMatchPreferences(),
        schedule: WeeklyDigestSchedule.sundayEvening,
        referenceDate: referenceDate
    )

    guard case .created(let snapshot) = firstResult else {
        Issue.record("Expected a created weekly digest snapshot.")
        return
    }

    #expect(snapshot.newApplicationsCount == 1)
    #expect(snapshot.interviewsScheduledCount == 1)

    let digests = try context.fetch(FetchDescriptor<WeeklyDigestSnapshot>())
    #expect(digests.count == 1)

    let secondResult = try service.generateLatestDigestIfNeeded(
        applications: [application],
        existingDigests: digests,
        in: context,
        currentResumeRevisionID: nil,
        matchPreferences: JobMatchPreferences(),
        schedule: WeeklyDigestSchedule.sundayEvening,
        referenceDate: referenceDate
    )

    guard case .existing(let existing) = secondResult else {
        Issue.record("Expected the existing digest to be reused on the second pass.")
        return
    }

    #expect(existing.id == snapshot.id)
    #expect(try context.fetch(FetchDescriptor<WeeklyDigestSnapshot>()).count == 1)
}

@Test func weeklyDigestPrioritizesFollowUpHygieneInsight() throws {
    let container = try makeWeeklyDigestContainer()
    let context = ModelContext(container)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let service = WeeklyDigestService(calendar: calendar)
    let referenceDate = makeDigestDate("2026-03-11T12:00:00Z")

    let first = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeDigestDate("2026-03-04T10:00:00Z"),
        nextFollowUpDate: makeDigestDate("2026-03-05T09:00:00Z")
    )
    let second = JobApplication(
        companyName: "Anthropic",
        role: "Platform Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeDigestDate("2026-03-06T10:00:00Z"),
        nextFollowUpDate: makeDigestDate("2026-03-06T09:00:00Z")
    )

    context.insert(first)
    context.insert(second)
    try context.save()

    let result = try service.generateLatestDigestIfNeeded(
        applications: [first, second],
        existingDigests: [],
        in: context,
        currentResumeRevisionID: nil,
        matchPreferences: JobMatchPreferences(),
        schedule: WeeklyDigestSchedule.sundayEvening,
        referenceDate: referenceDate
    )

    guard case .created(let snapshot) = result else {
        Issue.record("Expected a created weekly digest snapshot.")
        return
    }

    #expect(snapshot.overdueFollowUpsCount == 2)
    #expect(snapshot.sortedInsights.first?.title == "Follow-up hygiene is slipping.")
}

@Test func weeklyDigestIncludesRejectionLearningInsightWhenSnapshotIsFresh() throws {
    let container = try makeWeeklyDigestContainer()
    let context = ModelContext(container)

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let service = WeeklyDigestService(calendar: calendar)
    let referenceDate = makeDigestDate("2026-03-11T12:00:00Z")

    let apps = (0..<3).map { index in
        JobApplication(
            companyName: "Company \(index)",
            role: "Senior Engineer",
            location: "Remote",
            status: .rejected,
            appliedDate: makeDigestDate("2026-03-0\(index + 2)T10:00:00Z"),
            updatedAt: makeDigestDate("2026-03-0\(index + 3)T10:00:00Z")
        )
    }

    for application in apps {
        context.insert(application)
        let activity = ApplicationActivity(
            kind: .statusChange,
            occurredAt: application.updatedAt,
            application: application,
            interviewStage: .technicalRound1,
            toStatus: .rejected
        )
        let log = RejectionLog(
            stageCategory: .technical,
            reasonCategory: .skillsMismatch,
            feedbackSource: .explicit,
            feedbackText: "Needed stronger systems examples.",
            activity: activity
        )
        context.insert(activity)
        context.insert(log)
        application.addActivity(activity)
        activity.rejectionLog = log
    }

    let snapshot = RejectionLearningSnapshot(
        patternSignals: ["Technical-round rejections are repeating across similar roles."],
        targetingSignals: ["Senior titles are trending weaker than adjacent mid-level roles."],
        processSignals: ["Most logs still rely on inferred rather than explicit feedback."],
        recoverySuggestions: ["Prioritize technical refresh before retrying similar jobs."],
        rejectionCount: 3,
        explicitFeedbackCount: 3,
        generatedAt: makeDigestDate("2026-03-10T12:00:00Z")
    )
    context.insert(snapshot)
    try context.save()

    let result = try service.generateLatestDigestIfNeeded(
        applications: apps,
        existingDigests: [],
        in: context,
        currentResumeRevisionID: nil,
        matchPreferences: JobMatchPreferences(),
        schedule: WeeklyDigestSchedule.sundayEvening,
        referenceDate: referenceDate
    )

    guard case .created(let digest) = result else {
        Issue.record("Expected a created weekly digest snapshot.")
        return
    }

    #expect(digest.sortedInsights.contains(where: { $0.sourceKind == .ai }))
    #expect(digest.sortedInsights.contains(where: { $0.title == "Rejection patterns are starting to repeat." }))
    #expect(digest.sortedActionItems.contains(where: { $0.title == "Technical rounds are the current bottleneck." }))
}

private func makeWeeklyDigestContainer() throws -> ModelContainer {
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
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        JobMatchAssessment.self,
        ATSCompatibilityAssessment.self,
        ATSCompatibilityScanRun.self,
        AIUsageRecord.self,
        AIModelRate.self,
        WeeklyDigestSnapshot.self,
        WeeklyDigestInsight.self,
        WeeklyDigestActionItem.self
    ])

    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: configuration)
}

private func makeDigestDate(_ rawValue: String) -> Date {
    ISO8601DateFormatter().date(from: rawValue)!
}
