import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func checklistServiceSeedsStageTemplatesWithoutDuplicates() throws {
    let container = try makeChecklistContainer()
    let context = ModelContext(container)
    let service = ApplicationChecklistService(calendar: fixedCalendar)

    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeChecklistDate("2026-03-01")
    )
    context.insert(application)

    try service.sync(for: application, trigger: .applicationCreated, in: context)
    try service.sync(for: application, trigger: .statusChanged, in: context)

    let templateIDs = Set(application.sortedChecklistTasks.compactMap(\.checklistTemplateID))
    #expect(templateIDs == Set([
        "tailorResume",
        "generateCoverLetter",
        "researchCompany",
        "findReferral",
        "submitApplication",
        "followUpOnApplication"
    ]))
    #expect(application.sortedChecklistTasks.count == 6)
}

@Test func checklistServiceSkipsRejectedAndArchivedApplications() throws {
    let container = try makeChecklistContainer()
    let context = ModelContext(container)
    let service = ApplicationChecklistService(calendar: fixedCalendar)

    let rejected = JobApplication(
        companyName: "Example",
        role: "Engineer",
        location: "Remote",
        status: .rejected
    )
    let archived = JobApplication(
        companyName: "Example",
        role: "Designer",
        location: "Remote",
        status: .archived
    )

    context.insert(rejected)
    context.insert(archived)

    try service.sync(for: rejected, trigger: .applicationCreated, in: context)
    try service.sync(for: archived, trigger: .applicationCreated, in: context)

    #expect(rejected.sortedChecklistTasks.isEmpty)
    #expect(archived.sortedChecklistTasks.isEmpty)
}

@Test func dismissedChecklistItemsDoNotReseedOnLaterSyncs() throws {
    let container = try makeChecklistContainer()
    let context = ModelContext(container)
    let service = ApplicationChecklistService(calendar: fixedCalendar)

    let application = JobApplication(
        companyName: "OpenAI",
        role: "Engineer",
        location: "Remote",
        status: .saved
    )
    context.insert(application)

    try service.sync(for: application, trigger: .applicationCreated, in: context)

    let task = try #require(application.sortedChecklistTasks.first(where: { $0.checklistTemplateID == "generateCoverLetter" }))
    application.dismissChecklistTemplate(id: "generateCoverLetter")
    context.delete(task)
    application.tasks?.removeAll(where: { $0.id == task.id })
    try context.save()

    try service.sync(for: application, trigger: .detailViewed, in: context)

    #expect(application.dismissedChecklistTemplateIDs.contains("generateCoverLetter"))
    #expect(application.sortedChecklistTasks.contains(where: { $0.checklistTemplateID == "generateCoverLetter" }) == false)
}

@Test func checklistServiceAutoCompletesStrongSignalItemsOnly() throws {
    let container = try makeChecklistContainer()
    let context = ModelContext(container)
    let service = ApplicationChecklistService(calendar: fixedCalendar)

    let company = CompanyProfile(name: "OpenAI")
    let researchSnapshot = CompanyResearchSnapshot(
        providerID: "openai",
        model: "gpt-test",
        requestStatus: .succeeded,
        summaryText: "Strong research",
        finishedAt: makeChecklistDate("2026-03-04")
    )
    researchSnapshot.company = company
    company.researchSnapshots = [researchSnapshot]

    let application = JobApplication(
        companyName: "OpenAI",
        role: "Staff Engineer",
        location: "Remote",
        status: .offered,
        appliedDate: makeChecklistDate("2026-03-01"),
        company: company
    )

    let resumeSnapshot = ResumeJobSnapshot(rawJSON: #"{"name":"Candidate"}"#)
    resumeSnapshot.application = application
    application.resumeSnapshots = [resumeSnapshot]

    let coverLetter = CoverLetterDraft(plainText: "Cover letter body", application: application)
    application.assignCoverLetterDraft(coverLetter)

    let recruiterLink = ApplicationContactLink(application: application, role: .recruiter)
    let interviewerLink = ApplicationContactLink(application: application, role: .interviewer)
    application.contactLinks = [recruiterLink, interviewerLink]

    context.insert(company)
    context.insert(researchSnapshot)
    context.insert(application)
    context.insert(resumeSnapshot)
    context.insert(coverLetter)
    context.insert(recruiterLink)
    context.insert(interviewerLink)

    try service.sync(for: application, trigger: .statusChanged, in: context)

    let completedTemplateIDs = Set(
        application.sortedChecklistTasks
            .filter(\.isCompleted)
            .compactMap(\.checklistTemplateID)
    )

    #expect(completedTemplateIDs.contains("tailorResume"))
    #expect(completedTemplateIDs.contains("generateCoverLetter"))
    #expect(completedTemplateIDs.contains("researchCompany"))
    #expect(completedTemplateIDs.contains("findReferral"))
    #expect(completedTemplateIDs.contains("submitApplication"))
    #expect(completedTemplateIDs.contains("researchInterviewer"))
    #expect(completedTemplateIDs.contains("reviewInterviewPrep") == false)
    #expect(completedTemplateIDs.contains("compareOfferDetails") == false)
}

@Test func checklistServiceAssignsDueDatesToFollowUpAndThankYouItems() throws {
    let container = try makeChecklistContainer()
    let context = ModelContext(container)
    let service = ApplicationChecklistService(calendar: fixedCalendar)

    let application = JobApplication(
        companyName: "OpenAI",
        role: "Engineer",
        location: "Remote",
        status: .interviewing,
        appliedDate: makeChecklistDate("2026-03-01")
    )
    let interviewLog = InterviewLog(
        interviewType: .technicalRound1,
        date: makeChecklistDate("2026-03-03"),
        application: application
    )
    application.interviewLogs = [interviewLog]

    context.insert(application)
    context.insert(interviewLog)

    try service.sync(for: application, trigger: .interviewLogged, in: context)

    let followUpTask = try #require(application.sortedChecklistTasks.first(where: { $0.checklistTemplateID == "followUpOnApplication" }))
    let thankYouTask = try #require(application.sortedChecklistTasks.first(where: { $0.checklistTemplateID == "sendThankYouNote" }))

    #expect(followUpTask.dueDate == makeChecklistDate("2026-03-08"))
    #expect(thankYouTask.dueDate == makeChecklistDate("2026-03-04"))
}

private func makeChecklistContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        InterviewLog.self,
        CompanyProfile.self,
        CompanyResearchSnapshot.self,
        CompanyResearchSource.self,
        CompanySalarySnapshot.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self,
        ApplicationTask.self,
        ApplicationChecklistSuggestion.self,
        ApplicationAttachment.self,
        CoverLetterDraft.self,
        ATSCompatibilityAssessment.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private let fixedCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
}()

private func makeChecklistDate(_ value: String) -> Date {
    let formatter = DateFormatter()
    formatter.calendar = fixedCalendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.date(from: value) ?? Date()
}
