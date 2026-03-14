import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func googleCalendarMatchingPrefersCompanyAndRoleSignal() throws {
    let matchingApplication = JobApplication(
        companyName: "Stripe",
        role: "Senior iOS Engineer",
        location: "Remote"
    )
    let nonMatchingApplication = JobApplication(
        companyName: "Figma",
        role: "Product Designer",
        location: "New York"
    )

    let event = GoogleCalendarEventPayload(
        calendarID: "primary",
        calendarName: "Primary",
        eventID: "evt-1",
        etag: "etag-1",
        status: "confirmed",
        htmlLink: nil,
        summary: "Stripe Senior iOS Engineer technical interview",
        location: "Google Meet",
        details: "Chat with the Stripe mobile team.",
        organizerEmail: "recruiting@stripe.com",
        startDate: Date(timeIntervalSinceReferenceDate: 100),
        endDate: Date(timeIntervalSinceReferenceDate: 4600),
        isAllDay: false
    )

    let suggestion = GoogleCalendarMatchingService.bestMatch(
        for: event,
        among: [nonMatchingApplication, matchingApplication]
    )

    #expect(suggestion?.application.companyName == "Stripe")
    #expect(suggestion?.score ?? 0 > 70)
}

@MainActor
@Test func acceptingGoogleCalendarImportCreatesInterviewActivityAndPromotesStatus() async throws {
    let container = try makeGoogleCalendarContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Stripe",
        role: "iOS Engineer",
        location: "Remote",
        status: .applied
    )
    let record = GoogleCalendarImportRecord(
        remoteCalendarID: "primary",
        remoteCalendarName: "Primary",
        remoteEventID: "evt-2",
        remoteETag: "etag-2",
        summary: "Stripe iOS Engineer phone screen",
        location: "Google Meet",
        details: "Recruiter intro with hiring team context.",
        organizerEmail: "recruiting@stripe.com",
        startDate: Date(timeIntervalSinceReferenceDate: 10_000),
        endDate: Date(timeIntervalSinceReferenceDate: 13_600)
    )

    context.insert(application)
    context.insert(record)
    try context.save()

    try await GoogleCalendarImportCoordinator.shared.acceptImport(record, into: application, in: context)

    #expect(record.state == .imported)
    #expect(record.importedActivity?.kind == .interview)
    #expect(record.importedActivity?.scheduledDurationMinutes == 60)
    #expect(record.importedActivity?.interviewStage == .phoneScreen)
    #expect(record.importedActivity?.notes?.contains("Imported from Google Calendar") == true)
    #expect(application.status == .interviewing)
    #expect(application.sortedInterviewActivities.count == 1)
}

@MainActor
@Test func acceptingUpdateReusesExistingImportedActivity() async throws {
    let container = try makeGoogleCalendarContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Notion",
        role: "Product Engineer",
        location: "Remote",
        status: .interviewing
    )
    let activity = ApplicationActivity(
        kind: .interview,
        occurredAt: Date(timeIntervalSinceReferenceDate: 100),
        notes: "Old notes",
        application: application,
        interviewStage: .technicalRound1,
        scheduledDurationMinutes: 45
    )
    let record = GoogleCalendarImportRecord(
        remoteCalendarID: "team",
        remoteCalendarName: "Interview Loop",
        remoteEventID: "evt-3",
        remoteETag: "etag-3",
        summary: "Notion final interview",
        location: "Zoom",
        details: "Updated loop schedule.",
        organizerEmail: "interviews@notion.so",
        startDate: Date(timeIntervalSinceReferenceDate: 200),
        endDate: Date(timeIntervalSinceReferenceDate: 5_000),
        state: .updatePending,
        importedActivity: activity
    )

    context.insert(application)
    context.insert(activity)
    context.insert(record)
    application.addActivity(activity)
    try context.save()

    try await GoogleCalendarImportCoordinator.shared.acceptImport(record, into: application, in: context)

    #expect(record.state == .imported)
    #expect(record.importedActivity?.id == activity.id)
    #expect(application.sortedInterviewActivities.count == 1)
    #expect(activity.notes?.contains("Updated loop schedule.") == true)
    #expect(activity.scheduledDurationMinutes == 80)
}

private func makeGoogleCalendarContainer() throws -> ModelContainer {
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
        WeeklyDigestActionItem.self,
        GoogleCalendarAccount.self,
        GoogleCalendarSubscription.self,
        GoogleCalendarImportRecord.self,
        GoogleCalendarInterviewLink.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
