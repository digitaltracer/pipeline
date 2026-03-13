import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test func attachmentStorageCreatesManagedCopyAndResolvesPathAfterFetch() throws {
    let container = try makeAttachmentContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "OpenAI",
        role: "iOS Engineer",
        location: "Remote"
    )
    context.insert(application)
    try context.save()

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let service = ApplicationAttachmentStorageService(storageRootProvider: { tempRoot })
    let attachment = try service.createManagedFileAttachment(
        data: Data("resume".utf8),
        preferredFilename: "Resume Final.pdf",
        title: "Resume Final",
        contentType: "com.adobe.pdf",
        category: .resume,
        tags: ["resume", " Resume "],
        isSubmittedResume: true,
        for: application,
        in: context
    )

    let descriptor = FetchDescriptor<ApplicationAttachment>()
    let fetched = try context.fetch(descriptor)

    #expect(fetched.count == 1)
    #expect(fetched.first?.id == attachment.id)
    #expect(fetched.first?.tags == ["resume"])
    #expect(fetched.first?.managedStoragePath?.contains(application.id.uuidString) == true)
    #expect(application.submittedResumeAttachment?.id == attachment.id)

    let resolvedURL = try service.managedFileURL(for: attachment)
    let contents = try String(contentsOf: resolvedURL, encoding: .utf8)
    #expect(contents == "resume")
}

@Test func attachmentStorageDeletesManagedFileWithRecord() throws {
    let container = try makeAttachmentContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Stripe",
        role: "Engineer",
        location: "Remote"
    )
    context.insert(application)
    try context.save()

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let service = ApplicationAttachmentStorageService(storageRootProvider: { tempRoot })
    let attachment = try service.createManagedFileAttachment(
        data: Data("offer".utf8),
        preferredFilename: "Offer Letter.pdf",
        title: "Offer Letter",
        contentType: "com.adobe.pdf",
        category: .offer,
        for: application,
        in: context
    )

    let resolvedURL = try service.managedFileURL(for: attachment)
    #expect(FileManager.default.fileExists(atPath: resolvedURL.path))

    try service.deleteAttachment(attachment, from: application, in: context)

    #expect(!FileManager.default.fileExists(atPath: resolvedURL.path))
    #expect(try context.fetch(FetchDescriptor<ApplicationAttachment>()).isEmpty)
}

@Test func attachmentStoragePersistsLinksAndNotes() throws {
    let container = try makeAttachmentContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Anthropic",
        role: "Platform Engineer",
        location: "San Francisco"
    )
    context.insert(application)
    try context.save()

    let service = ApplicationAttachmentStorageService(storageRootProvider: { nil })
    let link = try service.createLinkAttachment(
        title: "Offer Portal",
        urlString: "example.com/offer",
        category: .link,
        tags: ["portal"],
        description: "Candidate portal",
        for: application,
        in: context
    )
    let note = try service.createNoteAttachment(
        title: "Negotiation Notes",
        body: "Need to ask about remote policy.",
        category: .note,
        tags: ["comp"],
        description: "Private note",
        for: application,
        in: context
    )

    #expect(link.normalizedExternalURL?.absoluteString == "https://example.com/offer")
    #expect(note.noteBody == "Need to ask about remote policy.")
    #expect(application.sortedAttachments.count == 2)
}

@Test func onlyOneSubmittedResumeRemainsMarked() throws {
    let container = try makeAttachmentContainer()
    let context = ModelContext(container)
    let application = JobApplication(
        companyName: "Apple",
        role: "iOS Engineer",
        location: "Cupertino"
    )
    context.insert(application)
    try context.save()

    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let service = ApplicationAttachmentStorageService(storageRootProvider: { tempRoot })
    let first = try service.createManagedFileAttachment(
        data: Data("first".utf8),
        preferredFilename: "Resume1.pdf",
        title: "Resume 1",
        contentType: "com.adobe.pdf",
        category: .resume,
        isSubmittedResume: true,
        for: application,
        in: context
    )
    let second = try service.createManagedFileAttachment(
        data: Data("second".utf8),
        preferredFilename: "Resume2.pdf",
        title: "Resume 2",
        contentType: "com.adobe.pdf",
        category: .resume,
        isSubmittedResume: false,
        for: application,
        in: context
    )

    try service.ensureSingleSubmittedResume(current: second, in: application, context: context)

    #expect(first.isSubmittedResume == false)
    #expect(second.isSubmittedResume == true)
    #expect(application.submittedResumeAttachment?.id == second.id)
}

private func makeAttachmentContainer() throws -> ModelContainer {
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
        ApplicationAttachment.self,
        CoverLetterDraft.self,
        ATSCompatibilityAssessment.self,
        ATSCompatibilityScanRun.self,
        ResumeMasterRevision.self,
        ResumeJobSnapshot.self,
        AIUsageRecord.self,
        AIModelRate.self
    ])
    let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
