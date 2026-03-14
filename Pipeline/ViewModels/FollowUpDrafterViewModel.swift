import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PipelineKit

@Observable
final class FollowUpDrafterViewModel {
    var isLoading = false
    var error: String?
    var result: FollowUpEmailResult?

    // Editable fields — initialized from AI result, user can modify
    var editableSubject: String = ""
    var editableBody: String = ""

    private let application: JobApplication
    private let followUpStep: FollowUpStep?
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext?

    init(
        application: JobApplication,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext? = nil,
        followUpStep: FollowUpStep? = nil
    ) {
        self.application = application
        self.followUpStep = followUpStep
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
        if let followUpStep,
           let subject = followUpStep.lastGeneratedSubject,
           let body = followUpStep.lastGeneratedBody {
            self.editableSubject = subject
            self.editableBody = body
            self.result = FollowUpEmailResult(subject: subject, body: body)
        }
    }

    var hasResult: Bool { result != nil }

    var applicationForLogging: JobApplication { application }

    var daysSinceLastContact: Int {
        let referenceDate: Date
        if let latestActivity = application.sortedActivities
            .first(where: isContactActivity) {
            referenceDate = latestActivity.occurredAt
        } else {
            referenceDate = application.updatedAt
        }

        return Calendar.current.dateComponents([.day], from: referenceDate, to: Date()).day ?? 0
    }

    @MainActor
    func generate() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return
        }

        let keys: [String]
        do {
            keys = try settingsViewModel.apiKeys(for: provider)
        } catch {
            self.error = "Could not access API key. Please check Settings."
            return
        }

        guard !keys.isEmpty else {
            error = "API key not configured for \(provider.rawValue). Please check Settings."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        result = nil
        defer { isLoading = false }

        // Gather current stage
        let stage: String
        if let latestInterview = application.sortedActivities
            .first(where: { $0.kind == .interview }) {
            stage = latestInterview.interviewStage?.displayName ?? latestInterview.kind.displayName
        } else {
            stage = application.status.displayName
        }

        let notes = notesContext()

        do {
            let emailResult = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await FollowUpDrafterService.generateFollowUp(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    company: application.companyName,
                    role: application.role,
                    stage: stage,
                    notes: notes,
                    daysSinceLastContact: daysSinceLastContact
                )
            }
            result = emailResult
            editableSubject = emailResult.subject
            editableBody = emailResult.body
            try persistDraftIfNeeded(subject: emailResult.subject, body: emailResult.body)
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: emailResult.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            self.error = "Failed to generate follow-up email: \(error.localizedDescription)"
            recordUsage(
                feature: .followUpDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: error.localizedDescription
            )
        }
    }

    func copyToClipboard() {
        let text = "Subject: \(editableSubject)\n\n\(editableBody)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    var mailtoURL: URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = application.primaryContactLink?.contact?.email ?? ""
        components.queryItems = [
            URLQueryItem(name: "subject", value: editableSubject),
            URLQueryItem(name: "body", value: editableBody)
        ]
        return components.url
    }

    private func notesContext() -> String {
        var sections: [String] = []

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Overview Notes:\n\(overview)")
        }

        let activityNotes = application.sortedActivities
            .filter { !$0.isSystemGenerated }
            .compactMap { activity -> String? in
                switch activity.kind {
                case .email:
                    return activity.emailBodySnapshot ?? activity.notes
                default:
                    return activity.notes
                }
            }
            .joined(separator: "\n")

        if !activityNotes.isEmpty {
            sections.append("Activity Notes:\n\(activityNotes)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func isContactActivity(_ activity: ApplicationActivity) -> Bool {
        guard !activity.isSystemGenerated else { return false }

        switch activity.kind {
        case .interview, .email, .call, .text:
            return true
        case .note:
            return activity.contact != nil
        case .statusChange, .followUp:
            return false
        }
    }

    private func recordUsage(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: feature,
            provider: provider,
            model: model,
            usage: usage,
            status: status,
            applicationID: application.id,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }

    @MainActor
    private func persistDraftIfNeeded(subject: String, body: String) throws {
        guard let followUpStep, let modelContext else { return }
        try SmartFollowUpService.shared.recordGeneratedDraft(
            subject: subject,
            body: body,
            for: followUpStep,
            application: application,
            in: modelContext
        )
    }
}

@Observable
final class ReferralRequestViewModel {
    var isLoading = false
    var error: String?
    var result: ReferralRequestDraftResult?
    var editableSubject: String = ""
    var editableBody: String = ""

    private let application: JobApplication
    private let importedConnection: ImportedNetworkConnection
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext

    init(
        application: JobApplication,
        importedConnection: ImportedNetworkConnection,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext
    ) {
        self.application = application
        self.importedConnection = importedConnection
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
    }

    var hasResult: Bool { result != nil }

    var displayName: String {
        importedConnection.linkedContact?.fullName ?? importedConnection.fullName
    }

    var relationship: String? {
        importedConnection.linkedContact?.relationship
    }

    var targetEmail: String? {
        importedConnection.linkedContact?.email ?? importedConnection.email
    }

    var canSendEmail: Bool {
        targetEmail?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var mailtoURL: URL? {
        guard let targetEmail else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = targetEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: editableSubject),
            URLQueryItem(name: "body", value: editableBody)
        ]
        return components.url
    }

    @MainActor
    func generate() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        result = nil
        defer { isLoading = false }

        let notes = referralNotesContext()
        let resumeJSON = (try? ResumeStoreService.currentMasterRevision(in: modelContext))?.rawJSON

        do {
            let draftResult = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await ReferralRequestDrafterService.generateDraft(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    company: application.companyName,
                    role: application.role,
                    contactName: displayName,
                    contactCompany: importedConnection.companyName,
                    relationship: relationship,
                    resumeJSON: resumeJSON,
                    notes: notes
                )
            }

            result = draftResult
            editableSubject = draftResult.subject
            editableBody = draftResult.body
            recordUsage(
                feature: .referralRequestDraft,
                provider: provider,
                model: model,
                usage: draftResult.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .referralRequestDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordUsage(
                feature: .referralRequestDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            let message = "Failed to draft referral request: \(error.localizedDescription)"
            self.error = message
            recordUsage(
                feature: .referralRequestDraft,
                provider: provider,
                model: model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: message
            )
        }
    }

    func copyToClipboard() {
        let text = "Subject: \(editableSubject)\n\n\(editableBody)"
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    @MainActor
    @discardableResult
    func logSentReferral(at occurredAt: Date = Date()) throws -> ReferralAttempt {
        let activityViewModel = ApplicationDetailViewModel()
        let contact = importedConnection.linkedContact

        try activityViewModel.saveActivity(
            nil,
            kind: .email,
            occurredAt: occurredAt,
            notes: "Referral outreach to \(displayName)",
            contact: contact,
            interviewStage: nil,
            scheduledDurationMinutes: nil,
            rating: nil,
            emailSubject: normalized(editableSubject),
            emailBodySnapshot: normalized(editableBody),
            for: application,
            context: modelContext
        )

        let activity = application.sortedActivities.first(where: {
            $0.kind == .email &&
            $0.occurredAt == occurredAt &&
            $0.emailSubject == normalized(editableSubject)
        })

        return try ReferralAttemptService.createAttempt(
            for: application,
            importedConnection: importedConnection,
            contact: contact,
            subject: normalized(editableSubject),
            body: normalized(editableBody),
            status: .asked,
            askedAt: occurredAt,
            sentEmailActivity: activity,
            in: modelContext
        )
    }

    private func referralNotesContext() -> String {
        var sections: [String] = []

        if let relationship = importedConnection.linkedContact?.relationship,
           !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("Relationship Context:\n\(relationship)")
        }

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Application Notes:\n\(overview)")
        }

        if let latestEmail = application.sortedActivities.first(where: { $0.kind == .email }),
           let body = latestEmail.emailBodySnapshot ?? latestEmail.notes {
            sections.append("Recent Outreach Notes:\n\(body)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func recordUsage(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        _ = try? AIUsageLedgerService.record(
            feature: feature,
            provider: provider,
            model: model,
            usage: usage,
            status: status,
            applicationID: application.id,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CoverLetterGenerationContext {
    let provider: AIProvider
    let model: String
    let jobDescription: String
    let notes: String
    let resumeSource: ResumeSourceSelection?
}

enum CoverLetterRegenerationTarget: Hashable {
    case greeting
    case hook
    case body(Int)
    case closing
}

@Observable
final class CoverLetterEditorViewModel {
    var isLoading = false
    var error: String?
    var notice: String?
    var editableTone: CoverLetterTone = .formal
    var editableGreeting: String = ""
    var editableHookParagraph: String = ""
    var editableBodyParagraphs: [String] = []
    var editableClosingParagraph: String = ""
    var lastAutosavedAt: Date?
    var regeneratingTargets = Set<CoverLetterRegenerationTarget>()
    #if os(macOS)
    var isExportingPDF = false
    #endif

    private let application: JobApplication
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext?
    private let attachmentStorageService = ApplicationAttachmentStorageService()
    private var draft: CoverLetterDraft?
    private var autosaveTask: Task<Void, Never>?

    init(
        application: JobApplication,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext? = nil
    ) {
        self.application = application
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
        self.draft = application.coverLetterDraft

        if let draft = application.coverLetterDraft {
            load(from: draft)
            lastAutosavedAt = draft.updatedAt
        }
    }

    deinit {
        autosaveTask?.cancel()
    }

    var hasResult: Bool {
        !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var plainText: String {
        CoverLetterDraft.composePlainText(
            greeting: editableGreeting,
            hookParagraph: editableHookParagraph,
            bodyParagraphs: editableBodyParagraphs,
            closingParagraph: editableClosingParagraph
        )
    }

    var sourceResumeLabel: String? {
        draft?.sourceResumeLabel
    }

    var autosaveStatusText: String? {
        guard let lastAutosavedAt else { return nil }
        return "Autosaved \(lastAutosavedAt.formatted(date: .omitted, time: .shortened))"
    }

    var companyName: String { application.companyName }

    var roleTitle: String { application.role }

    func updateTone(_ tone: CoverLetterTone) {
        editableTone = tone
        scheduleAutosave()
    }

    func updateGreeting(_ text: String) {
        editableGreeting = text
        scheduleAutosave()
    }

    func updateHookParagraph(_ text: String) {
        editableHookParagraph = text
        scheduleAutosave()
    }

    func updateBodyParagraph(_ text: String, at index: Int) {
        guard editableBodyParagraphs.indices.contains(index) else { return }
        editableBodyParagraphs[index] = text
        scheduleAutosave()
    }

    func updateClosingParagraph(_ text: String) {
        editableClosingParagraph = text
        scheduleAutosave()
    }

    func isRegenerating(_ target: CoverLetterRegenerationTarget) -> Bool {
        regeneratingTargets.contains(target)
    }

    @MainActor
    func generate() async {
        guard let context = preflightContext(requireResumeSource: true) else { return }

        autosaveTask?.cancel()
        let requestStartedAt = Date()
        isLoading = true
        error = nil
        notice = nil
        defer { isLoading = false }

        do {
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: context.provider) { apiKey in
                try await CoverLetterGenerationService.generateCoverLetter(
                    provider: context.provider,
                    apiKey: apiKey,
                    model: context.model,
                    tone: editableTone,
                    company: application.companyName,
                    role: application.role,
                    jobDescription: context.jobDescription,
                    notes: context.notes,
                    resumeJSON: context.resumeSource?.rawJSON ?? ""
                )
            }

            apply(result)
            try persistDraft(
                source: context.resumeSource,
                provider: context.provider,
                model: context.model,
                recordGenerationMetadata: true
            )
            notice = "Cover letter updated."
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: result.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            let message = error.localizedDescription
            self.error = "Failed to generate cover letter: \(message)"
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: message
            )
        }
    }

    @MainActor
    func regenerateSection(_ target: CoverLetterRegenerationTarget) async {
        guard let context = preflightContext(requireResumeSource: true),
              let currentDraft = currentDraftResult(for: target)
        else {
            return
        }

        autosaveTask?.cancel()
        let requestStartedAt = Date()
        regeneratingTargets.insert(target)
        error = nil
        notice = nil
        defer { regeneratingTargets.remove(target) }

        let section: CoverLetterSectionKind
        let paragraphIndex: Int?
        switch target {
        case .greeting:
            section = .greeting
            paragraphIndex = nil
        case .hook:
            section = .hook
            paragraphIndex = nil
        case .body(let index):
            section = .bodyParagraph
            paragraphIndex = index
        case .closing:
            section = .closing
            paragraphIndex = nil
        }

        do {
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: context.provider) { apiKey in
                try await CoverLetterGenerationService.regenerateSection(
                    provider: context.provider,
                    apiKey: apiKey,
                    model: context.model,
                    tone: editableTone,
                    section: section,
                    paragraphIndex: paragraphIndex,
                    currentDraft: currentDraft,
                    company: application.companyName,
                    role: application.role,
                    jobDescription: context.jobDescription,
                    notes: context.notes,
                    resumeJSON: context.resumeSource?.rawJSON ?? ""
                )
            }

            applyRegeneratedSection(result)
            try persistDraft(
                source: context.resumeSource,
                provider: context.provider,
                model: context.model,
                recordGenerationMetadata: true
            )
            notice = "\(section.displayName) updated."
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: result.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                errorMessage: nil
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: keyError.localizedDescription
            )
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: aiError.localizedDescription
            )
        } catch {
            let message = error.localizedDescription
            self.error = "Failed to regenerate section: \(message)"
            recordUsage(
                feature: .coverLetterDraft,
                provider: context.provider,
                model: context.model,
                usage: nil,
                status: .failed,
                startedAt: requestStartedAt,
                errorMessage: message
            )
        }
    }

    func copyToClipboard() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(plainText, forType: .string)
        #else
        UIPasteboard.general.string = plainText
        #endif
        notice = "Copied cover letter text."
    }

    @MainActor
    func saveTextVersion() {
        guard hasResult else { return }
        guard let modelContext else {
            error = "Cover letter storage is unavailable."
            return
        }

        do {
            try flushAutosaveIfNeeded()
            _ = try attachmentStorageService.createNoteAttachment(
                title: "Cover Letter \(versionTitleSuffix())",
                body: plainText,
                category: .coverLetter,
                description: "Saved cover letter version",
                for: application,
                in: modelContext
            )
            notice = "Saved text version to Documents."
        } catch {
            self.error = "Could not save text version: \(error.localizedDescription)"
        }
    }

    #if os(macOS)
    @MainActor
    func exportPDF() async {
        guard hasResult else { return }
        guard let modelContext else {
            error = "Cover letter storage is unavailable."
            return
        }

        isExportingPDF = true
        error = nil
        notice = nil
        defer { isExportingPDF = false }

        do {
            try flushAutosaveIfNeeded()
            let resumeJSON = try ResumeStoreService.preferredResumeSource(
                for: application,
                in: modelContext
            )?.rawJSON
            let document = try await CoverLetterPDFExportService.makeDocument(
                companyName: application.companyName,
                role: application.role,
                greeting: editableGreeting,
                hookParagraph: editableHookParagraph,
                bodyParagraphs: editableBodyParagraphs,
                closingParagraph: editableClosingParagraph,
                resumeJSON: resumeJSON
            )

            _ = try attachmentStorageService.createManagedFileAttachment(
                data: document.data,
                preferredFilename: coverLetterPDFFileName(),
                title: "Cover Letter",
                contentType: UTType.pdf.identifier,
                category: .coverLetter,
                for: application,
                in: modelContext
            )
            notice = "Saved PDF to Documents."
        } catch {
            self.error = "Could not export PDF: \(error.localizedDescription)"
        }
    }
    #endif

    private func currentDraftResult(for target: CoverLetterRegenerationTarget) -> CoverLetterGenerationResult? {
        guard hasResult else { return nil }

        switch target {
        case .body(let index):
            guard editableBodyParagraphs.indices.contains(index) else { return nil }
        case .greeting, .hook, .closing:
            break
        }

        return CoverLetterGenerationResult(
            greeting: editableGreeting,
            hookParagraph: editableHookParagraph,
            bodyParagraphs: editableBodyParagraphs,
            closingParagraph: editableClosingParagraph
        )
    }

    private func apply(_ result: CoverLetterGenerationResult) {
        editableGreeting = result.greeting
        editableHookParagraph = result.hookParagraph
        editableBodyParagraphs = result.bodyParagraphs
        editableClosingParagraph = result.closingParagraph
    }

    private func applyRegeneratedSection(_ result: CoverLetterSectionRegenerationResult) {
        switch result.section {
        case .greeting:
            editableGreeting = result.text
        case .hook:
            editableHookParagraph = result.text
        case .bodyParagraph:
            guard let paragraphIndex = result.paragraphIndex,
                  editableBodyParagraphs.indices.contains(paragraphIndex) else { return }
            editableBodyParagraphs[paragraphIndex] = result.text
        case .closing:
            editableClosingParagraph = result.text
        }
    }

    private func load(from draft: CoverLetterDraft) {
        editableTone = draft.tone
        editableGreeting = draft.greeting
        editableHookParagraph = draft.hookParagraph
        editableBodyParagraphs = draft.bodyParagraphs
        editableClosingParagraph = draft.closingParagraph
    }

    private func scheduleAutosave() {
        guard hasResult else { return }

        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self.persistAutosave()
        }
    }

    @MainActor
    private func persistAutosave() {
        do {
            try flushAutosaveIfNeeded()
            notice = nil
        } catch {
            self.error = "Could not autosave cover letter draft."
        }
    }

    private func flushAutosaveIfNeeded() throws {
        autosaveTask?.cancel()
        _ = try persistDraft(
            source: nil,
            provider: nil,
            model: nil,
            recordGenerationMetadata: false
        )
    }

    @discardableResult
    private func persistDraft(
        source: ResumeSourceSelection?,
        provider: AIProvider?,
        model: String?,
        recordGenerationMetadata: Bool
    ) throws -> CoverLetterDraft? {
        guard let modelContext else { return nil }

        let draft = try ensureDraft(in: modelContext)
        draft.applyEdits(
            tone: editableTone,
            greeting: editableGreeting,
            hookParagraph: editableHookParagraph,
            bodyParagraphs: editableBodyParagraphs,
            closingParagraph: editableClosingParagraph,
            shouldTouch: false
        )

        if recordGenerationMetadata {
            draft.recordGenerationMetadata(
                sourceResumeKind: source?.kind.rawValue ?? draft.sourceResumeKind,
                sourceResumeLabel: source?.label ?? draft.sourceResumeLabel,
                sourceResumeSnapshotID: source?.snapshotID ?? draft.sourceResumeSnapshotID,
                providerID: provider?.providerID ?? draft.lastGeneratedProviderID,
                model: model ?? draft.lastGeneratedModel,
                generatedAt: Date(),
                shouldTouch: false
            )
        }

        draft.refreshPlainText(shouldTouch: false)
        draft.updateTimestamp()
        application.updateTimestamp()
        try ApplicationChecklistService().sync(for: application, trigger: .coverLetterSaved, in: modelContext)
        lastAutosavedAt = draft.updatedAt
        self.draft = draft
        return draft
    }

    private func ensureDraft(in context: ModelContext) throws -> CoverLetterDraft {
        if let draft {
            return draft
        }

        let draft = CoverLetterDraft(tone: editableTone)
        draft.application = application
        application.assignCoverLetterDraft(draft)
        context.insert(draft)
        try context.save()
        self.draft = draft
        return draft
    }

    private func preflightContext(requireResumeSource: Bool) -> CoverLetterGenerationContext? {
        guard let jobDescription = application.jobDescription?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !jobDescription.isEmpty else {
            error = "This job is missing a job description. Add one in Edit Application before generating a cover letter."
            return nil
        }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return nil
        }

        do {
            let keys = try settingsViewModel.apiKeys(for: provider)
            guard !keys.isEmpty else {
                error = "API key not configured for \(provider.rawValue). Please check Settings."
                return nil
            }
        } catch {
            self.error = "Could not access API key. Please check Settings."
            return nil
        }

        let resumeSource: ResumeSourceSelection?
        if let modelContext {
            do {
                resumeSource = try ResumeStoreService.preferredResumeSource(
                    for: application,
                    in: modelContext
                )
            } catch {
                self.error = "Could not load your resume source."
                return nil
            }
        } else {
            resumeSource = nil
        }

        if requireResumeSource, resumeSource == nil {
            error = "Save a master resume or tailor this job's resume before generating a cover letter."
            return nil
        }

        return CoverLetterGenerationContext(
            provider: provider,
            model: model,
            jobDescription: jobDescription,
            notes: notesContext(),
            resumeSource: resumeSource
        )
    }

    private func notesContext() -> String {
        var sections: [String] = []

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Overview Notes:\n\(overview)")
        }

        let activityNotes = application.sortedActivities
            .filter { !$0.isSystemGenerated }
            .compactMap { activity -> String? in
                switch activity.kind {
                case .email:
                    return activity.emailBodySnapshot ?? activity.notes
                default:
                    return activity.notes
                }
            }
            .joined(separator: "\n")

        if !activityNotes.isEmpty {
            sections.append("Activity Notes:\n\(activityNotes)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func recordUsage(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        startedAt: Date,
        errorMessage: String?
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: feature,
            provider: provider,
            model: model,
            usage: usage,
            status: status,
            applicationID: application.id,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }

    private func versionTitleSuffix() -> String {
        Date().formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }

    private func coverLetterPDFFileName() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MM-yy"

        let sanitizedCompany = application.companyName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(
                of: #"[^a-z0-9]+"#,
                with: "-",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let companyPart = sanitizedCompany.isEmpty ? "job" : sanitizedCompany
        return "\(companyPart)-cover-letter-\(formatter.string(from: Date())).pdf"
    }
}
