import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func interviewLearningBuilderAggregatesQuestionBankAndBoostsRelevantHistory() throws {
    let container = try makeInterviewLearningContainer()
    let context = ModelContext(container)
    let builder = InterviewLearningContextBuilder()

    let target = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing,
        interviewStage: .systemDesign
    )
    let matchingSource = JobApplication(
        companyName: "OpenAI",
        role: "Senior iOS Engineer",
        location: "Remote",
        status: .interviewing
    )
    let otherSource = JobApplication(
        companyName: "Stripe",
        role: "Backend Engineer",
        location: "Remote",
        status: .interviewing
    )

    let matchingActivity = makeInterviewActivity(
        application: matchingSource,
        occurredAt: date("2026-03-01T10:00:00Z"),
        stage: .systemDesign,
        question: "Design a notification fanout system.",
        category: .systemDesign,
        confidence: 2
    )
    let otherActivity = makeInterviewActivity(
        application: otherSource,
        occurredAt: date("2026-02-20T10:00:00Z"),
        stage: .technicalRound1,
        question: "Walk through a hashmap implementation.",
        category: .coding,
        confidence: 5
    )

    context.insert(target)
    context.insert(matchingSource)
    context.insert(otherSource)
    context.insert(matchingActivity)
    context.insert(otherActivity)
    try context.save()

    let learningContext = builder.build(from: [target, matchingSource, otherSource])
    #expect(learningContext.questionCount == 2)
    #expect(learningContext.debriefCount == 2)
    #expect(learningContext.categoryCounts.first?.category == .coding || learningContext.categoryCounts.first?.category == .systemDesign)

    let personalized = builder.personalizedPrepContext(for: target, in: [target, matchingSource, otherSource])
    #expect(personalized.boostedQuestions.first?.companyName == "OpenAI")
    #expect(personalized.boostedQuestions.first?.interviewStage == .systemDesign)
}

@Test func interviewPrepUserContextIncludesPersonalHistoryInputs() {
    let userContext = InterviewPrepService.buildUserContext(
        role: "iOS Engineer",
        company: "OpenAI",
        jobDescription: "Ship product features.",
        interviewStage: "System Design",
        notes: "Strong UIKit background.",
        personalQuestionBankContext: "- [System Design] Design a queue",
        learningSummary: "Strength: behavioral answers"
    )

    #expect(userContext.contains("Personal Question Bank"))
    #expect(userContext.contains("Interview Learning Summary"))
    #expect(userContext.contains("Design a queue"))
}

@Test func interviewLearningParserHandlesMixedJsonText() throws {
    let payload = """
    Here you go:
    ```json
    {
      "strengths": ["Behavioral answers are consistent."],
      "growthAreas": ["System design confidence dips late in loops."],
      "recurringThemes": ["Fintech interviews emphasize distributed systems."],
      "companyPatterns": ["OpenAI asked product-minded architecture questions."],
      "recommendedFocusAreas": ["Practice system design tradeoffs out loud."]
    }
    ```
    """

    let parsed = try InterviewLearningService.parseResponse(payload)
    #expect(parsed.strengths == ["Behavioral answers are consistent."])
    #expect(parsed.growthAreas.count == 1)
    #expect(parsed.companyPatterns.first?.contains("OpenAI") == true)
}

@Test func debriefReminderDateIsThirtyMinutesAfterInterviewEndWhenStillInFuture() {
    let futureEnd = Date().addingTimeInterval(90 * 60)
    let reminderDate = NotificationService.debriefReminderDate(for: futureEnd)
    let expected = futureEnd.addingTimeInterval(30 * 60)

    #expect(reminderDate != nil)
    #expect(abs((reminderDate ?? .distantPast).timeIntervalSince(expected)) < 1)
}

private func makeInterviewLearningContainer() throws -> ModelContainer {
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
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private func makeInterviewActivity(
    application: JobApplication,
    occurredAt: Date,
    stage: InterviewStage,
    question: String,
    category: InterviewQuestionCategory,
    confidence: Int
) -> ApplicationActivity {
    let activity = ApplicationActivity(
        kind: .interview,
        occurredAt: occurredAt,
        application: application,
        interviewStage: stage,
        scheduledDurationMinutes: 60
    )
    let debrief = InterviewDebrief(
        confidence: confidence,
        whatWentWell: "Kept the structure tight.",
        activity: activity
    )
    let entry = InterviewQuestionEntry(
        prompt: question,
        category: category,
        answerNotes: "Talked through tradeoffs.",
        debrief: debrief
    )

    activity.debrief = debrief
    debrief.questionEntries = [entry]
    if application.activities == nil {
        application.activities = []
    }
    application.activities?.append(activity)
    return activity
}

private func date(_ value: String) -> Date {
    let formatter = ISO8601DateFormatter()
    return formatter.date(from: value) ?? Date()
}
