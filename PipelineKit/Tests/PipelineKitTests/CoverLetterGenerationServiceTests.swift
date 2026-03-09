import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func coverLetterGenerationParsesStrictJSON() throws {
    let rawJSON = """
    {
      "greeting": "Dear Hiring Team,",
      "hookParagraph": "I am excited to apply for the Senior iOS Engineer role at Apple.",
      "bodyParagraphs": [
        "At OpenAI, I built SwiftUI product surfaces and shipped user-facing AI workflows.",
        "I also led reliability improvements that map directly to your platform engineering needs."
      ],
      "closingParagraph": "Thank you for your time and consideration. Best regards,"
    }
    """

    let result = try CoverLetterGenerationService.parseGenerationResponse(rawJSON)

    #expect(result.greeting == "Dear Hiring Team,")
    #expect(result.bodyParagraphs.count == 2)
    #expect(result.plainText.contains("Best regards,"))
}

@Test func coverLetterGenerationRejectsMalformedJSON() {
    #expect(throws: Error.self) {
        try CoverLetterGenerationService.parseGenerationResponse("not json")
    }
}

@Test func coverLetterSectionRegenerationParsesReplacementText() throws {
    let rawJSON = """
    {
      "text": "I have repeatedly translated product requirements into measurable SwiftUI delivery."
    }
    """

    let result = try CoverLetterGenerationService.parseRegenerationResponse(
        rawJSON,
        section: .bodyParagraph,
        paragraphIndex: 1
    )

    #expect(result.section == .bodyParagraph)
    #expect(result.paragraphIndex == 1)
    #expect(result.text.contains("SwiftUI"))
}

@Test func coverLetterPromptsPreserveToneChoice() {
    let prompts = CoverLetterGenerationService.generationPrompts(
        tone: .enthusiastic,
        company: "Apple",
        role: "Senior iOS Engineer",
        jobDescription: "Build user-facing product experiences.",
        notes: "Interested in platform polish.",
        resumeJSON: "{\"name\":\"Ada\"}"
    )

    #expect(prompts.systemPrompt.contains("energetic, confident, and positive"))
    #expect(prompts.userPrompt.contains("Enthusiastic"))

    let currentDraft = CoverLetterGenerationResult(
        greeting: "Dear Hiring Team,",
        hookParagraph: "Hook",
        bodyParagraphs: ["Body 1", "Body 2"],
        closingParagraph: "Best regards,"
    )
    let sectionPrompts = CoverLetterGenerationService.sectionRegenerationPrompts(
        tone: .conversational,
        section: .bodyParagraph,
        paragraphIndex: 0,
        currentDraft: currentDraft,
        company: "Apple",
        role: "Senior iOS Engineer",
        jobDescription: "Build user-facing product experiences.",
        notes: "",
        resumeJSON: "{\"name\":\"Ada\"}"
    )

    #expect(sectionPrompts.systemPrompt.contains("warm, approachable, and human"))
    #expect(sectionPrompts.userPrompt.contains("Body paragraph 1"))
}

@Test func preferredResumeSourceUsesLatestTailoredSnapshotBeforeMaster() throws {
    let container = try makeCoverLetterContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Apple",
        role: "Senior iOS Engineer",
        location: "Cupertino"
    )
    context.insert(application)
    try context.save()

    _ = try ResumeStoreService.saveMasterRevision(
        rawJSON: "{\"name\":\"Master\"}",
        unknownFieldPaths: [],
        in: context
    )
    let snapshot = try ResumeStoreService.createJobSnapshot(
        for: application,
        rawJSON: "{\"name\":\"Tailored\"}",
        acceptedPatchIDs: [],
        rejectedPatchIDs: [],
        sectionGaps: [],
        sourceMasterRevisionID: nil,
        in: context
    )

    let source = try ResumeStoreService.preferredResumeSource(for: application, in: context)

    #expect(source?.kind == .tailoredSnapshot)
    #expect(source?.snapshotID == snapshot.id)
    #expect(source?.rawJSON.contains("Tailored") == true)
}

@Test func preferredResumeSourceFallsBackToMaster() throws {
    let container = try makeCoverLetterContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Apple",
        role: "Senior iOS Engineer",
        location: "Cupertino"
    )
    context.insert(application)
    try context.save()

    _ = try ResumeStoreService.saveMasterRevision(
        rawJSON: "{\"name\":\"Master\"}",
        unknownFieldPaths: [],
        in: context
    )

    let source = try ResumeStoreService.preferredResumeSource(for: application, in: context)

    #expect(source?.kind == .masterResume)
    #expect(source?.snapshotID == nil)
    #expect(source?.rawJSON.contains("Master") == true)
}

@Test func coverLetterAttachmentsPersistWithoutAffectingResumeAttachments() throws {
    let container = try makeCoverLetterContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Apple",
        role: "Senior iOS Engineer",
        location: "Cupertino"
    )
    context.insert(application)
    try context.save()

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let service = ApplicationAttachmentStorageService(storageRootProvider: { tempRoot })
    let resume = try service.createManagedFileAttachment(
        data: Data("resume".utf8),
        preferredFilename: "Resume.pdf",
        title: "Resume",
        contentType: "com.adobe.pdf",
        category: .resume,
        isSubmittedResume: true,
        for: application,
        in: context
    )
    let coverLetter = try service.createNoteAttachment(
        title: "Cover Letter",
        body: "Dear Hiring Team,",
        category: .coverLetter,
        for: application,
        in: context
    )

    #expect(resume.category == .resume)
    #expect(coverLetter.category == .coverLetter)
    #expect(application.submittedResumeAttachment?.id == resume.id)
    #expect(application.sortedAttachments.contains(where: { $0.id == coverLetter.id }))
}

private func makeCoverLetterContainer() throws -> ModelContainer {
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
        ApplicationTask.self,
        ApplicationChecklistSuggestion.self,
        ApplicationAttachment.self,
        CoverLetterDraft.self,
        ATSCompatibilityAssessment.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        AIUsageRecord.self,
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
