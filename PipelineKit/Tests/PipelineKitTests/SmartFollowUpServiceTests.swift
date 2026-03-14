import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@MainActor
@Test func smartFollowUpServiceCreatesAppliedCadence() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeFollowUpDate("2026-03-03T09:00:00Z")
    )
    context.insert(application)

    try service.ensureAppliedCadence(for: application, in: context)

    #expect(application.activeFollowUpSteps.count == 5)
    #expect(application.activeFollowUpSteps.map(\.kind) == [.ackCheck, .followUp1, .followUp2, .followUp3, .archiveSuggestion])
    #expect(application.nextPendingFollowUpStep?.kind == .ackCheck)
    #expect(application.nextPendingFollowUpStep?.dueDate == makeFollowUpDate("2026-03-06T10:00:00Z"))
    #expect(application.sortedFollowUpSteps.first(where: { $0.kind == .followUp1 })?.dueDate == makeFollowUpDate("2026-03-10T10:00:00Z"))
}

@MainActor
@Test func smartFollowUpServiceAvoidsWeekendAndMondayForOutboundSteps() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let application = JobApplication(
        companyName: "Linear",
        role: "Product Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeFollowUpDate("2026-03-02T09:00:00Z")
    )
    context.insert(application)

    try service.ensureAppliedCadence(for: application, in: context)

    #expect(application.sortedFollowUpSteps.first(where: { $0.kind == .ackCheck })?.dueDate == makeFollowUpDate("2026-03-05T10:00:00Z"))
    #expect(application.sortedFollowUpSteps.first(where: { $0.kind == .followUp1 })?.dueDate == makeFollowUpDate("2026-03-10T10:00:00Z"))
}

@MainActor
@Test func smartFollowUpServiceUsesCompanyResponseSpeedWhenScheduling() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let previousA = JobApplication(
        companyName: "Stripe",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing,
        appliedDate: makeFollowUpDate("2026-03-01T09:00:00Z")
    )
    let previousB = JobApplication(
        companyName: "Stripe",
        role: "Senior iOS Engineer",
        location: "Remote",
        status: .interviewing,
        appliedDate: makeFollowUpDate("2026-03-05T09:00:00Z")
    )
    let current = JobApplication(
        companyName: "Stripe",
        role: "Staff iOS Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeFollowUpDate("2026-03-12T09:00:00Z")
    )

    let activityA = ApplicationActivity(
        kind: .statusChange,
        occurredAt: makeFollowUpDate("2026-03-02T09:00:00Z"),
        application: previousA,
        toStatus: .interviewing
    )
    let activityB = ApplicationActivity(
        kind: .statusChange,
        occurredAt: makeFollowUpDate("2026-03-08T09:00:00Z"),
        application: previousB,
        toStatus: .interviewing
    )
    previousA.activities = [activityA]
    previousB.activities = [activityB]

    context.insert(previousA)
    context.insert(previousB)
    context.insert(current)
    context.insert(activityA)
    context.insert(activityB)

    try service.ensureAppliedCadence(for: current, in: context)

    #expect(current.sortedFollowUpSteps.first(where: { $0.kind == .followUp1 })?.dueDate == makeFollowUpDate("2026-03-18T10:00:00Z"))
}

@MainActor
@Test func smartFollowUpServiceAddsThankYouAndRebasesAfterInterview() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let application = JobApplication(
        companyName: "Ramp",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing,
        appliedDate: makeFollowUpDate("2026-03-03T09:00:00Z")
    )
    context.insert(application)
    try service.ensureAppliedCadence(for: application, in: context)

    let interview = ApplicationActivity(
        kind: .interview,
        occurredAt: makeFollowUpDate("2026-03-13T15:00:00Z"),
        application: application,
        interviewStage: .technicalRound1
    )
    context.insert(interview)
    application.addActivity(interview)
    try service.syncInterviewCadence(for: application, in: context)

    #expect(application.sortedFollowUpSteps.first(where: { $0.kind == .postInterviewThankYou })?.dueDate == makeFollowUpDate("2026-03-17T10:00:00Z"))
    #expect(application.sortedFollowUpSteps.first(where: { $0.kind == .followUp1 && $0.cadenceKind == .applicationApplied })?.dueDate == makeFollowUpDate("2026-03-18T10:00:00Z"))
}

@MainActor
@Test func smartFollowUpServiceSnoozeAndCompleteAdvanceMirror() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let application = JobApplication(
        companyName: "Notion",
        role: "Product Engineer",
        location: "Remote",
        status: .applied,
        appliedDate: makeFollowUpDate("2026-03-03T09:00:00Z")
    )
    context.insert(application)
    try service.ensureAppliedCadence(for: application, in: context)

    let firstStep = try #require(application.nextPendingFollowUpStep)
    try service.snoozeStep(firstStep, by: 3, for: application, in: context)
    #expect(application.nextFollowUpDate == makeFollowUpDate("2026-03-09T10:00:00Z"))

    try service.markStepDone(firstStep, for: application, in: context)
    #expect(application.nextPendingFollowUpStep?.kind == .followUp1)
    #expect(application.nextFollowUpDate == makeFollowUpDate("2026-03-10T10:00:00Z"))
}

@MainActor
@Test func smartFollowUpServiceBackfillsLegacyManualStep() throws {
    let container = try makeSmartFollowUpContainer()
    let context = ModelContext(container)
    let service = SmartFollowUpService(calendar: fixedFollowUpCalendar)

    let application = JobApplication(
        companyName: "Figma",
        role: "Designer",
        location: "Remote",
        status: .saved,
        nextFollowUpDate: makeFollowUpDate("2026-03-18T10:00:00Z")
    )
    context.insert(application)

    _ = try service.refresh(application, in: context)
    try context.save()

    #expect(application.sortedFollowUpSteps.count == 1)
    #expect(application.sortedFollowUpSteps.first?.kind == .legacyManual)
    #expect(application.nextPendingFollowUpStep?.dueDate == makeFollowUpDate("2026-03-18T10:00:00Z"))
}

private func makeSmartFollowUpContainer() throws -> ModelContainer {
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
        ResumeJobSnapshot.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private let fixedFollowUpCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
}()

private func makeFollowUpDate(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: value) ?? Date()
}
