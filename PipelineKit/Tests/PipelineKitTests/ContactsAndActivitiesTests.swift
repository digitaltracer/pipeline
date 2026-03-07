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

private func makeContactsContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        JobSearchCycle.self,
        SearchGoal.self,
        InterviewLog.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
