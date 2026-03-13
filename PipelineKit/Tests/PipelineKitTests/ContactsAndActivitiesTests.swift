import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func contactRelationshipsExposeLinkedApplicationsAndActivities() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Stripe",
        role: "iOS Engineer",
        location: "Remote"
    )
    let contact = Contact(
        fullName: "Avery Chen",
        email: "avery@example.com",
        companyName: "Stripe"
    )
    let link = ApplicationContactLink(
        application: application,
        contact: contact,
        role: .recruiter,
        isPrimary: true
    )
    let activity = ApplicationActivity(
        kind: .email,
        occurredAt: Date(),
        notes: "Shared recruiter follow-up.",
        emailSubject: "Checking in",
        application: application,
        contact: contact
    )

    context.insert(application)
    context.insert(contact)
    context.insert(link)
    context.insert(activity)
    application.addContactLink(link)
    application.addActivity(activity)
    try context.save()

    #expect(contact.linkedApplications.count == 1)
    #expect(contact.linkedApplications.first?.companyName == "Stripe")
    #expect(contact.sortedActivities.count == 1)
    #expect(application.primaryContactLink?.contact?.fullName == "Avery Chen")
}

@Test func migrationCreatesActivitiesAndReusesContactsIdempotently() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "San Francisco"
    )
    let firstLog = InterviewLog(
        interviewType: .phoneScreen,
        date: Date(),
        interviewerName: "Jordan Kim",
        rating: 4,
        notes: "Good intro call.",
        application: application
    )
    let secondLog = InterviewLog(
        interviewType: .systemDesign,
        date: Date().addingTimeInterval(3600),
        interviewerName: "Jordan Kim",
        rating: 5,
        notes: "Strong follow-up.",
        application: application
    )

    context.insert(application)
    context.insert(firstLog)
    context.insert(secondLog)
    application.addInterviewLog(firstLog)
    application.addInterviewLog(secondLog)
    try context.save()

    let firstPass = try ApplicationTimelineMigrationService.migrateLegacyInterviewLogs(in: context)
    let secondPass = try ApplicationTimelineMigrationService.migrateLegacyInterviewLogs(in: context)

    let activities = try context.fetch(FetchDescriptor<ApplicationActivity>())
    let contacts = try context.fetch(FetchDescriptor<Contact>())

    #expect(firstPass == 2)
    #expect(secondPass == 0)
    #expect(activities.count == 2)
    #expect(contacts.count == 1)
    #expect(application.sortedActivities.count == 2)
    #expect(application.sortedContactLinks.count == 1)
    #expect(firstLog.migratedActivityID != nil)
    #expect(secondLog.migratedActivityID != nil)
}

@Test func migrationSkipsBlankInterviewerNamesButStillCreatesActivities() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Acme",
        role: "Platform Engineer",
        location: "Remote"
    )
    let log = InterviewLog(
        interviewType: .technicalRound1,
        date: Date(),
        interviewerName: "   ",
        rating: 3,
        notes: "Whiteboard exercise.",
        application: application
    )

    context.insert(application)
    context.insert(log)
    application.addInterviewLog(log)
    try context.save()

    let migrated = try ApplicationTimelineMigrationService.migrateLegacyInterviewLogs(in: context)
    let activities = try context.fetch(FetchDescriptor<ApplicationActivity>())
    let contacts = try context.fetch(FetchDescriptor<Contact>())

    #expect(migrated == 1)
    #expect(activities.count == 1)
    #expect(contacts.isEmpty)
    #expect(activities.first?.contact == nil)
}

@Test func migrationKeepsSameNameSeparatedAcrossCompanies() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let firstApplication = JobApplication(
        companyName: "Apple",
        role: "Engineer",
        location: "Cupertino"
    )
    let secondApplication = JobApplication(
        companyName: "Google",
        role: "Engineer",
        location: "Mountain View"
    )

    let firstLog = InterviewLog(
        interviewType: .phoneScreen,
        interviewerName: "Sam Lee",
        application: firstApplication
    )
    let secondLog = InterviewLog(
        interviewType: .phoneScreen,
        interviewerName: "Sam Lee",
        application: secondApplication
    )

    context.insert(firstApplication)
    context.insert(secondApplication)
    context.insert(firstLog)
    context.insert(secondLog)
    firstApplication.addInterviewLog(firstLog)
    secondApplication.addInterviewLog(secondLog)
    try context.save()

    _ = try ApplicationTimelineMigrationService.migrateLegacyInterviewLogs(in: context)
    let contacts = try context.fetch(FetchDescriptor<Contact>())

    #expect(contacts.count == 2)
    #expect(Set(contacts.compactMap(\.companyName)) == ["Apple", "Google"])
}

@Test func overviewMarkdownPersistsOnApplication() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Notion",
        role: "iOS Engineer",
        location: "Remote",
        overviewMarkdown: """
        ## Recruiter context
        - Warm intro from Dana
        - Team is hiring for platform work
        """
    )

    context.insert(application)
    try context.save()

    let fetched = try context.fetch(FetchDescriptor<JobApplication>())
    #expect(fetched.count == 1)
    #expect(fetched.first?.overviewMarkdown?.contains("Recruiter context") == true)
}

@Test func statusChangeRecorderCreatesStructuredActivityAndSkipsDuplicates() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Figma",
        role: "iOS Engineer",
        location: "Remote"
    )
    context.insert(application)

    ApplicationTimelineRecorderService.recordStatusChange(
        for: application,
        from: .saved,
        to: .applied,
        occurredAt: Date(timeIntervalSinceReferenceDate: 10),
        in: context
    )
    ApplicationTimelineRecorderService.recordStatusChange(
        for: application,
        from: .applied,
        to: .applied,
        occurredAt: Date(timeIntervalSinceReferenceDate: 20),
        in: context
    )

    try context.save()

    let activities = try context.fetch(FetchDescriptor<ApplicationActivity>())
    #expect(activities.count == 1)
    #expect(activities.first?.kind == .statusChange)
    #expect(activities.first?.fromStatus == .saved)
    #expect(activities.first?.toStatus == .applied)
    #expect(activities.first?.isSystemGenerated == true)
}

@Test @MainActor func statusTransitionServiceReturnsPromptForRejectedApplications() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Arc",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing,
        interviewStage: .technicalRound2
    )
    context.insert(application)

    let result = try ApplicationStatusTransitionService.applyStatus(.rejected, to: application, in: context)

    #expect(result.didChange == true)
    #expect(result.needsRejectionLogPrompt == true)
    #expect(application.status == .rejected)
    #expect(application.latestRejectionActivity?.toStatus == .rejected)
    #expect(application.latestRejectionActivity?.interviewStage == .technicalRound2)
    #expect(application.needsRejectionLog == true)
}

@Test func rejectionLogAttachesToRejectedStatusActivity() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Notion",
        role: "Product Engineer",
        location: "Remote",
        status: .rejected
    )
    context.insert(application)
    ApplicationTimelineRecorderService.seedInitialHistory(for: application, in: context)

    guard let activity = application.latestRejectionActivity else {
        Issue.record("Expected a rejection status activity.")
        return
    }

    let log = RejectionLog(
        stageCategory: .technical,
        reasonCategory: .skillsMismatch,
        feedbackSource: .explicit,
        feedbackText: "Needed deeper API design examples.",
        activity: activity
    )
    context.insert(log)
    activity.rejectionLog = log
    try context.save()

    #expect(activity.hasRejectionLog == true)
    #expect(activity.needsRejectionLog == false)
    #expect(application.latestRejectionLog?.reasonCategory == .skillsMismatch)
}

@Test func followUpRecorderTracksSetRescheduleAndClear() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Linear",
        role: "iOS Engineer",
        location: "Remote"
    )
    context.insert(application)

    let firstDate = Date(timeIntervalSinceReferenceDate: 100)
    let secondDate = Date(timeIntervalSinceReferenceDate: 200)

    ApplicationTimelineRecorderService.recordFollowUpChange(
        for: application,
        from: nil,
        to: firstDate,
        occurredAt: Date(timeIntervalSinceReferenceDate: 10),
        in: context
    )
    ApplicationTimelineRecorderService.recordFollowUpChange(
        for: application,
        from: firstDate,
        to: secondDate,
        occurredAt: Date(timeIntervalSinceReferenceDate: 20),
        in: context
    )
    ApplicationTimelineRecorderService.recordFollowUpChange(
        for: application,
        from: secondDate,
        to: nil,
        occurredAt: Date(timeIntervalSinceReferenceDate: 30),
        in: context
    )

    try context.save()

    let activities = application.sortedActivities
    #expect(activities.count == 3)
    #expect(activities[0].kind == .followUp)
    #expect(activities[0].fromFollowUpDate == secondDate)
    #expect(activities[0].toFollowUpDate == nil)
    #expect(activities[1].fromFollowUpDate == firstDate)
    #expect(activities[1].toFollowUpDate == secondDate)
    #expect(activities[2].fromFollowUpDate == nil)
    #expect(activities[2].toFollowUpDate == firstDate)
}

@Test func initialHistorySeedingCreatesStatusAndFollowUpEvents() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let followUpDate = Date(timeIntervalSinceReferenceDate: 300)
    let application = JobApplication(
        companyName: "OpenAI",
        role: "Product Engineer",
        location: "San Francisco",
        status: .interviewing,
        nextFollowUpDate: followUpDate
    )

    context.insert(application)
    ApplicationTimelineRecorderService.seedInitialHistory(
        for: application,
        occurredAt: Date(timeIntervalSinceReferenceDate: 10),
        in: context
    )
    try context.save()

    let activities = application.sortedActivities
    #expect(activities.count == 2)
    #expect(Set(activities.map(\.kind)) == [.statusChange, .followUp])
    #expect(activities.first(where: { $0.kind == .statusChange })?.toStatus == .interviewing)
    #expect(activities.first(where: { $0.kind == .followUp })?.toFollowUpDate == followUpDate)
}

@Test func sortedActivitiesOrderMixedManualAndSystemEntriesChronologically() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Ramp",
        role: "iOS Engineer",
        location: "New York"
    )
    context.insert(application)

    let note = ApplicationActivity(
        kind: .note,
        occurredAt: Date(timeIntervalSinceReferenceDate: 50),
        notes: "Manual note",
        application: application
    )
    context.insert(note)
    application.addActivity(note)

    ApplicationTimelineRecorderService.recordStatusChange(
        for: application,
        from: .saved,
        to: .applied,
        occurredAt: Date(timeIntervalSinceReferenceDate: 100),
        in: context
    )
    ApplicationTimelineRecorderService.recordFollowUpChange(
        for: application,
        from: nil,
        to: Date(timeIntervalSinceReferenceDate: 400),
        occurredAt: Date(timeIntervalSinceReferenceDate: 150),
        in: context
    )

    try context.save()

    let activities = application.sortedActivities
    #expect(activities.map(\.kind) == [.followUp, .statusChange, .note])
}

@Test func applicationTasksPersistPriorityCompletionAndOrdering() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Vercel",
        role: "Product Engineer",
        location: "Remote"
    )
    context.insert(application)

    let datedTask = ApplicationTask(
        title: "Prepare STAR stories",
        notes: "Focus on cross-functional projects.",
        dueDate: Date(timeIntervalSinceReferenceDate: 200),
        priority: .high,
        application: application
    )
    let backlogTask = ApplicationTask(
        title: "Research company values",
        priority: .medium,
        application: application
    )

    context.insert(datedTask)
    context.insert(backlogTask)
    application.addTask(datedTask)
    application.addTask(backlogTask)

    datedTask.setCompleted(true)
    backlogTask.priority = .low

    try context.save()

    let fetchedTasks = try context.fetch(FetchDescriptor<ApplicationTask>())
    #expect(fetchedTasks.count == 2)
    #expect(datedTask.isCompleted == true)
    #expect(datedTask.completedAt != nil)
    #expect(backlogTask.priority == .low)
    #expect(application.sortedTasks.first?.id == backlogTask.id)
    #expect(application.sortedTasks.last?.id == datedTask.id)
}

@Test func deletingApplicationCascadesTasks() throws {
    let container = try makeContactsContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Anthropic",
        role: "iOS Engineer",
        location: "San Francisco"
    )
    let task = ApplicationTask(
        title: "Send thank-you note",
        dueDate: Date(timeIntervalSinceReferenceDate: 100),
        application: application
    )

    context.insert(application)
    context.insert(task)
    application.addTask(task)
    try context.save()

    context.delete(application)
    try context.save()

    let remainingTasks = try context.fetch(FetchDescriptor<ApplicationTask>())
    #expect(remainingTasks.isEmpty)
}

private func makeContactsContainer() throws -> ModelContainer {
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
        ApplicationChecklistSuggestion.self,
        ATSCompatibilityAssessment.self,
        ATSCompatibilityScanRun.self,
        CoverLetterDraft.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
