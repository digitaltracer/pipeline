import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@Observable
final class ApplicationDetailViewModel {
    enum SaveValidationError: LocalizedError {
        case emptyActivity
        case emptyTaskTitle
        case emptySalaryRole

        var errorDescription: String? {
            switch self {
            case .emptyActivity:
                return "Add some notes or activity details before saving."
            case .emptyTaskTitle:
                return "Enter a task title before saving."
            case .emptySalaryRole:
                return "Enter a role title before saving this salary snapshot."
            }
        }
    }

    private let checklistService = ApplicationChecklistService()

    // MARK: - Actions

    func archive(_ application: JobApplication, context: ModelContext) throws {
        let previousStatus = application.status
        application.status = .archived
        application.updateTimestamp()
        ApplicationTimelineRecorderService.recordStatusChange(
            for: application,
            from: previousStatus,
            to: application.status,
            in: context
        )

        do {
            try syncChecklist(for: application, trigger: .statusChanged, context: context)
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func delete(_ application: JobApplication, context: ModelContext) throws {
        context.delete(application)
        do {
            try context.save()
            Task { await NotificationService.shared.removeNotifications(for: application.id) }
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateStatus(_ status: ApplicationStatus, for application: JobApplication, context: ModelContext) throws {
        let previousStatus = application.status
        application.status = status
        application.updateTimestamp()

        // If moving to interviewing, set applied date if not set
        if status == .interviewing && application.appliedDate == nil {
            application.appliedDate = Date()
        }

        // If moving to applied, set applied date
        if status == .applied && application.appliedDate == nil {
            application.appliedDate = Date()
        }

        ApplicationTimelineRecorderService.recordStatusChange(
            for: application,
            from: previousStatus,
            to: application.status,
            in: context
        )

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateInterviewStage(_ stage: InterviewStage?, for application: JobApplication, context: ModelContext) throws {
        let previousStage = application.interviewStage
        application.interviewStage = stage
        application.updateTimestamp()
        do {
            try context.save()
        } catch {
            application.interviewStage = previousStage
            throw error
        }
    }

    func updatePriority(_ priority: Priority, for application: JobApplication, context: ModelContext) throws {
        let previousPriority = application.priority
        application.priority = priority
        application.updateTimestamp()
        do {
            try context.save()
        } catch {
            application.priority = previousPriority
            throw error
        }
    }

    func saveOverviewMarkdown(_ markdown: String?, for application: JobApplication, context: ModelContext) throws {
        let previousMarkdown = application.overviewMarkdown
        application.overviewMarkdown = markdown
        application.updateTimestamp()

        do {
            try context.save()
        } catch {
            application.overviewMarkdown = previousMarkdown
            throw error
        }
    }

    @discardableResult
    func ensureCompanyProfile(for application: JobApplication, context: ModelContext) throws -> CompanyProfile {
        let company = try CompanyLinkingService.ensureCompanyLinked(for: application, in: context)
        try context.save()
        return company
    }

    func saveCompanyProfile(
        _ company: CompanyProfile,
        name: String,
        websiteURL: String?,
        linkedInURL: String?,
        glassdoorURL: String?,
        levelsFYIURL: String?,
        teamBlindURL: String?,
        industry: String?,
        sizeBand: CompanySizeBand?,
        headquarters: String?,
        userRating: Int?,
        notesMarkdown: String?,
        context: ModelContext
    ) throws {
        let previousName = company.name
        let previousNormalizedName = company.normalizedName
        let previousWebsite = company.websiteURL
        let previousLinkedIn = company.linkedInURL
        let previousGlassdoor = company.glassdoorURL
        let previousLevels = company.levelsFYIURL
        let previousBlind = company.teamBlindURL
        let previousIndustry = company.industry
        let previousSizeBand = company.sizeBand
        let previousHeadquarters = company.headquarters
        let previousRating = company.userRating
        let previousNotes = company.notesMarkdown

        company.rename(name)
        company.setWebsiteURL(websiteURL)
        company.setLinkedInURL(linkedInURL)
        company.setGlassdoorURL(glassdoorURL)
        company.setLevelsFYIURL(levelsFYIURL)
        company.setTeamBlindURL(teamBlindURL)
        company.setIndustry(industry)
        company.sizeBand = sizeBand
        company.setHeadquarters(headquarters)
        company.setUserRating(userRating)
        company.setNotesMarkdown(notesMarkdown)

        do {
            try context.save()
        } catch {
            company.name = previousName
            company.normalizedName = previousNormalizedName
            company.websiteURL = previousWebsite
            company.linkedInURL = previousLinkedIn
            company.glassdoorURL = previousGlassdoor
            company.levelsFYIURL = previousLevels
            company.teamBlindURL = previousBlind
            company.industry = previousIndustry
            company.sizeBand = previousSizeBand
            company.headquarters = previousHeadquarters
            company.userRating = previousRating
            company.notesMarkdown = previousNotes
            throw error
        }
    }

    func saveCompanySalarySnapshot(
        _ existingSnapshot: CompanySalarySnapshot?,
        company: CompanyProfile,
        roleTitle: String,
        location: String,
        sourceName: String,
        sourceURLString: String?,
        notes: String?,
        confidenceNotes: String?,
        currency: Currency,
        minBaseCompensation: Int?,
        maxBaseCompensation: Int?,
        minTotalCompensation: Int?,
        maxTotalCompensation: Int?,
        context: ModelContext
    ) throws {
        let trimmedRole = roleTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRole.isEmpty else {
            throw SaveValidationError.emptySalaryRole
        }

        let normalizedSourceName = sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSourceName = normalizedSourceName.isEmpty ? "Manual" : normalizedSourceName

        if let existingSnapshot {
            existingSnapshot.update(
                roleTitle: trimmedRole,
                location: location,
                sourceName: resolvedSourceName,
                sourceURLString: sourceURLString,
                notes: notes,
                confidenceNotes: confidenceNotes,
                currency: currency,
                minBaseCompensation: minBaseCompensation,
                maxBaseCompensation: maxBaseCompensation,
                minTotalCompensation: minTotalCompensation,
                maxTotalCompensation: maxTotalCompensation,
                isUserEdited: true
            )
            existingSnapshot.capturedAt = Date()
        } else {
            let snapshot = CompanySalarySnapshot(
                roleTitle: trimmedRole,
                location: location,
                sourceName: resolvedSourceName,
                sourceURLString: sourceURLString,
                notes: notes,
                confidenceNotes: confidenceNotes,
                currency: currency,
                minBaseCompensation: minBaseCompensation,
                maxBaseCompensation: maxBaseCompensation,
                minTotalCompensation: minTotalCompensation,
                maxTotalCompensation: maxTotalCompensation,
                isUserEdited: true,
                capturedAt: Date(),
                company: company
            )
            context.insert(snapshot)
        }

        company.touchSalaryResearch()

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteCompanySalarySnapshot(
        _ snapshot: CompanySalarySnapshot,
        context: ModelContext
    ) throws {
        context.delete(snapshot)
        do {
            refreshDerivedResearchState(for: snapshot.company)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteCompanyResearchSource(
        _ source: CompanyResearchSource,
        context: ModelContext
    ) throws {
        let company = source.company
        context.delete(source)
        do {
            refreshDerivedResearchState(for: company)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteCompanyResearchSnapshot(
        _ snapshot: CompanyResearchSnapshot,
        context: ModelContext
    ) throws {
        let company = snapshot.company
        context.delete(snapshot)
        do {
            refreshDerivedResearchState(for: company)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func saveTask(
        _ existingTask: ApplicationTask?,
        title: String,
        notes: String?,
        dueDate: Date?,
        priority: Priority,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw SaveValidationError.emptyTaskTitle }

        let task: ApplicationTask
        if let existingTask {
            task = existingTask
        } else {
            task = ApplicationTask(
                title: normalizedTitle,
                notes: notes,
                dueDate: dueDate,
                priority: priority,
                application: application
            )
            context.insert(task)
            application.addTask(task)
        }

        task.title = normalizedTitle
        task.notes = notes
        task.dueDate = dueDate
        task.priority = priority
        task.updateTimestamp()
        application.updateTimestamp()

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncTaskReminder(for: task)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func setTaskCompletion(
        _ isCompleted: Bool,
        for task: ApplicationTask,
        in application: JobApplication,
        context: ModelContext
    ) throws {
        task.setCompleted(isCompleted)
        application.updateTimestamp()

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncTaskReminder(for: task)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteTask(_ task: ApplicationTask, from application: JobApplication, context: ModelContext) throws {
        let taskID = task.id
        let applicationID = application.id

        if task.isSmartChecklistItem, let templateID = task.checklistTemplateID {
            application.dismissChecklistTemplate(id: templateID)
        }

        context.delete(task)
        application.tasks?.removeAll(where: { $0.id == taskID })
        application.updateTimestamp()

        do {
            try context.save()
            Task {
                await NotificationService.shared.removeTaskNotifications(for: taskID, applicationID: applicationID)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func clearFollowUp(for application: JobApplication, context: ModelContext) throws {
        let previousFollowUpDate = application.nextFollowUpDate
        guard previousFollowUpDate != nil else { return }

        application.nextFollowUpDate = nil
        application.updateTimestamp()
        ApplicationTimelineRecorderService.recordFollowUpChange(
            for: application,
            from: previousFollowUpDate,
            to: nil,
            in: context
        )

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func addInterviewLog(_ log: InterviewLog, to application: JobApplication, context: ModelContext) throws {
        application.addInterviewLog(log)

        // Update interview stage if the log type is newer
        if let currentStage = application.interviewStage {
            if log.interviewType.sortOrder > currentStage.sortOrder {
                application.interviewStage = log.interviewType
            }
        } else {
            application.interviewStage = log.interviewType
        }

        // Ensure status is interviewing if not already
        if application.status == .applied || application.status == .saved {
            let previousStatus = application.status
            application.status = .interviewing
            ApplicationTimelineRecorderService.recordStatusChange(
                for: application,
                from: previousStatus,
                to: application.status,
                in: context
            )
        }

        do {
            try syncChecklist(for: application, trigger: .interviewLogged, context: context)
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteInterviewLog(_ log: InterviewLog, from application: JobApplication, context: ModelContext) throws {
        context.delete(log)
        application.updateTimestamp()
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func linkContact(
        _ contact: Contact,
        to application: JobApplication,
        role: ContactRole,
        markPrimary: Bool,
        context: ModelContext
    ) throws {
        _ = try upsertContactLink(
            contact,
            to: application,
            role: role,
            markPrimary: markPrimary,
            context: context
        )

        do {
            try syncChecklist(for: application, trigger: .contactsChanged, context: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func updateContactLink(
        _ link: ApplicationContactLink,
        role: ContactRole,
        isPrimary: Bool,
        in application: JobApplication,
        context: ModelContext
    ) throws {
        link.role = role
        link.isPrimary = isPrimary
        link.updateTimestamp()
        application.updateTimestamp()

        if isPrimary {
            setPrimary(link, in: application)
        }

        do {
            try syncChecklist(for: application, trigger: .contactsChanged, context: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func unlinkContact(
        _ link: ApplicationContactLink,
        from application: JobApplication,
        context: ModelContext
    ) throws {
        let wasPrimary = link.isPrimary
        context.delete(link)
        application.contactLinks?.removeAll(where: { $0.id == link.id })
        application.updateTimestamp()

        if wasPrimary, let replacement = application.contactLinks?.first {
            replacement.isPrimary = true
            replacement.updateTimestamp()
        }

        do {
            try syncChecklist(for: application, trigger: .contactsChanged, context: context)
        } catch {
            context.rollback()
            throw error
        }
    }

    func saveActivity(
        _ existingActivity: ApplicationActivity?,
        kind: ApplicationActivityKind,
        occurredAt: Date,
        notes: String?,
        contact: Contact?,
        interviewStage: InterviewStage?,
        scheduledDurationMinutes: Int?,
        rating: Int?,
        emailSubject: String?,
        emailBodySnapshot: String?,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        guard hasMeaningfulContent(
            kind: kind,
            notes: notes,
            interviewStage: interviewStage,
            emailSubject: emailSubject,
            emailBodySnapshot: emailBodySnapshot
        ) else {
            throw SaveValidationError.emptyActivity
        }

        let activity: ApplicationActivity
        if let existingActivity {
            activity = existingActivity
        } else {
            activity = ApplicationActivity(kind: kind, application: application)
            context.insert(activity)
            application.addActivity(activity)
        }

        activity.kind = kind
        activity.occurredAt = occurredAt
        activity.notes = notes
        activity.contact = contact
        activity.interviewStage = kind == .interview ? interviewStage : nil
        activity.scheduledDurationMinutes = kind == .interview ? scheduledDurationMinutes : nil
        activity.rating = kind == .interview ? rating : nil
        activity.emailSubject = kind == .email ? emailSubject : nil
        activity.emailBodySnapshot = kind == .email ? emailBodySnapshot : nil
        activity.updateTimestamp()
        application.updateTimestamp()

        if let contact {
            let role = defaultContactRole(for: kind)
            _ = try upsertContactLink(
                contact,
                to: application,
                role: role,
                markPrimary: application.primaryContactLink == nil,
                context: context
            )
        }

        syncInterviewState(for: application, context: context)

        do {
            try syncChecklist(for: application, trigger: .statusChanged, context: context)
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteActivity(_ activity: ApplicationActivity, from application: JobApplication, context: ModelContext) throws {
        guard !activity.isSystemGenerated else { return }

        context.delete(activity)
        application.activities?.removeAll(where: { $0.id == activity.id })
        application.updateTimestamp()
        syncInterviewState(for: application, context: context)

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    // MARK: - Helpers

    private func defaultContactRole(for kind: ApplicationActivityKind) -> ContactRole {
        switch kind {
        case .interview:
            return .interviewer
        case .email, .call, .text:
            return .recruiter
        case .note, .statusChange, .followUp:
            return .other
        }
    }

    private func hasMeaningfulContent(
        kind: ApplicationActivityKind,
        notes: String?,
        interviewStage: InterviewStage?,
        emailSubject: String?,
        emailBodySnapshot: String?
    ) -> Bool {
        switch kind {
        case .interview:
            return interviewStage != nil || notes != nil
        case .email:
            return emailSubject != nil || emailBodySnapshot != nil || notes != nil
        case .call, .text, .note:
            return notes != nil
        case .statusChange, .followUp:
            return false
        }
    }

    private func setPrimary(_ link: ApplicationContactLink, in application: JobApplication) {
        for candidate in application.contactLinks ?? [] {
            candidate.isPrimary = candidate.id == link.id
            candidate.updateTimestamp()
        }
    }

    private func upsertContactLink(
        _ contact: Contact,
        to application: JobApplication,
        role: ContactRole,
        markPrimary: Bool,
        context: ModelContext
    ) throws -> ApplicationContactLink {
        if let existing = application.contactLinks?.first(where: { $0.contact?.id == contact.id }) {
            existing.role = role
            existing.isPrimary = markPrimary || existing.isPrimary
            existing.updateTimestamp()
            application.updateTimestamp()

            if existing.isPrimary {
                setPrimary(existing, in: application)
            }

            return existing
        }

        let link = ApplicationContactLink(
            application: application,
            contact: contact,
            role: role,
            isPrimary: markPrimary
        )
        context.insert(link)
        application.addContactLink(link)
        contact.mergeCompanyNameIfMissing(application.companyName)
        contact.updateTimestamp()

        if markPrimary {
            setPrimary(link, in: application)
        }

        return link
    }

    private func syncInterviewState(for application: JobApplication, context: ModelContext) {
        let latestInterviewStage = application.sortedActivities
            .filter { $0.kind == .interview }
            .compactMap(\.interviewStage)
            .sorted { $0.sortOrder > $1.sortOrder }
            .first

        application.interviewStage = latestInterviewStage

        if latestInterviewStage != nil && (application.status == .saved || application.status == .applied) {
            let previousStatus = application.status
            application.status = .interviewing
            ApplicationTimelineRecorderService.recordStatusChange(
                for: application,
                from: previousStatus,
                to: application.status,
                in: context
            )
        }
    }

    private func refreshDerivedResearchState(for company: CompanyProfile?) {
        guard let company else { return }

        let latestSnapshot = company.sortedResearchSnapshots.first
        company.lastResearchSummary = latestSnapshot?.summaryText
        company.lastResearchedAt = latestSnapshot?.finishedAt

        let latestSalarySnapshot = company.sortedSalarySnapshots.first
        company.lastSalaryResearchAt = latestSalarySnapshot?.capturedAt
        company.updateTimestamp()
    }

    private func syncChecklist(
        for application: JobApplication,
        trigger: ApplicationChecklistSyncTrigger,
        context: ModelContext
    ) throws {
        try checklistService.sync(for: application, trigger: trigger, in: context)
    }
}

@Observable
final class InterviewDebriefViewModel {
    struct QuestionDraft: Identifiable, Equatable {
        let id: UUID
        var prompt: String
        var category: InterviewQuestionCategory
        var answerNotes: String
        var interviewerHint: String

        init(
            id: UUID = UUID(),
            prompt: String = "",
            category: InterviewQuestionCategory = .behavioral,
            answerNotes: String = "",
            interviewerHint: String = ""
        ) {
            self.id = id
            self.prompt = prompt
            self.category = category
            self.answerNotes = answerNotes
            self.interviewerHint = interviewerHint
        }
    }

    struct FollowUpDraft: Identifiable, Equatable {
        let id: UUID
        var title: String
        var notes: String

        init(id: UUID = UUID(), title: String = "", notes: String = "") {
            self.id = id
            self.title = title
            self.notes = notes
        }
    }

    var confidence: Int = 3
    var whatWentWell: String = ""
    var wouldDoDifferently: String = ""
    var overallNotes: String = ""
    var questions: [QuestionDraft] = []
    var followUpItems: [FollowUpDraft] = []
    var errorMessage: String?

    private let activity: ApplicationActivity
    private let application: JobApplication
    private let modelContext: ModelContext

    init(activity: ApplicationActivity, application: JobApplication, modelContext: ModelContext) {
        self.activity = activity
        self.application = application
        self.modelContext = modelContext

        if let debrief = activity.debrief {
            confidence = debrief.confidence
            whatWentWell = debrief.whatWentWell ?? ""
            wouldDoDifferently = debrief.wouldDoDifferently ?? ""
            overallNotes = debrief.overallNotes ?? ""
            questions = debrief.sortedQuestionEntries.map {
                QuestionDraft(
                    id: $0.id,
                    prompt: $0.prompt,
                    category: $0.category,
                    answerNotes: $0.answerNotes ?? "",
                    interviewerHint: $0.interviewerHint ?? ""
                )
            }
        }

        if questions.isEmpty {
            questions = [QuestionDraft()]
        }
        if followUpItems.isEmpty {
            followUpItems = [FollowUpDraft()]
        }
    }

    func addQuestion() {
        questions.append(QuestionDraft())
    }

    func removeQuestion(id: UUID) {
        questions.removeAll { $0.id == id }
        if questions.isEmpty {
            questions = [QuestionDraft()]
        }
    }

    func addFollowUpItem() {
        followUpItems.append(FollowUpDraft())
    }

    func removeFollowUpItem(id: UUID) {
        followUpItems.removeAll { $0.id == id }
        if followUpItems.isEmpty {
            followUpItems = [FollowUpDraft()]
        }
    }

    func save() throws {
        let debrief: InterviewDebrief
        if let existing = activity.debrief {
            debrief = existing
        } else {
            debrief = InterviewDebrief(activity: activity)
            modelContext.insert(debrief)
            activity.debrief = debrief
        }

        debrief.update(
            confidence: confidence,
            whatWentWell: normalized(whatWentWell),
            wouldDoDifferently: normalized(wouldDoDifferently),
            overallNotes: normalized(overallNotes)
        )
        activity.updateTimestamp()
        application.updateTimestamp()

        let existingQuestions = Dictionary(uniqueKeysWithValues: debrief.sortedQuestionEntries.map { ($0.id, $0) })
        let incomingQuestions = questions.enumerated().compactMap { index, draft -> (UUID, QuestionDraft, Int)? in
            guard let prompt = normalized(draft.prompt) else { return nil }
            return (draft.id, QuestionDraft(
                id: draft.id,
                prompt: prompt,
                category: draft.category,
                answerNotes: draft.answerNotes,
                interviewerHint: draft.interviewerHint
            ), index)
        }

        let incomingIDs = Set(incomingQuestions.map(\.0))
        for question in debrief.sortedQuestionEntries where !incomingIDs.contains(question.id) {
            modelContext.delete(question)
        }
        debrief.questionEntries?.removeAll { !incomingIDs.contains($0.id) }

        for (id, draft, orderIndex) in incomingQuestions {
            if let existing = existingQuestions[id] {
                existing.update(
                    prompt: draft.prompt,
                    category: draft.category,
                    answerNotes: normalized(draft.answerNotes),
                    interviewerHint: normalized(draft.interviewerHint),
                    orderIndex: orderIndex
                )
            } else {
                let question = InterviewQuestionEntry(
                    id: id,
                    prompt: draft.prompt,
                    category: draft.category,
                    answerNotes: normalized(draft.answerNotes),
                    interviewerHint: normalized(draft.interviewerHint),
                    orderIndex: orderIndex,
                    debrief: debrief
                )
                modelContext.insert(question)
                if debrief.questionEntries == nil {
                    debrief.questionEntries = []
                }
                debrief.questionEntries?.append(question)
            }
        }

        try createFollowUpTasksIfNeeded(for: debrief)
        try modelContext.save()

        Task { @MainActor in
            await NotificationService.shared.syncReminderState(for: application)
        }
    }

    private func createFollowUpTasksIfNeeded(for debrief: InterviewDebrief) throws {
        let existingTaskIDs = Set(debrief.createdTaskIDs)
        var existingTaskTitles = Set(application.sortedTasks.map { normalizeForLookup($0.displayTitle) })

        for draft in followUpItems {
            guard let title = normalized(draft.title) else { continue }
            let normalizedTitle = normalizeForLookup(title)
            guard !existingTaskTitles.contains(normalizedTitle) else { continue }

            let task = ApplicationTask(
                title: title,
                notes: normalized(draft.notes),
                priority: .medium,
                application: application,
                origin: .manual
            )
            modelContext.insert(task)
            application.addTask(task)
            existingTaskTitles.insert(normalizedTitle)
            if !existingTaskIDs.contains(task.id) {
                debrief.appendCreatedTaskID(task.id)
            }
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func normalizeForLookup(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

@MainActor
@Observable
final class InterviewLearningsViewModel {
    var isLoading = false
    var error: String?
    var snapshot: InterviewLearningSnapshot?
    var questionBankEntries: [InterviewQuestionBankEntry] = []
    var fallbackSnapshot: InterviewLearningSnapshot?

    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext
    private let builder = InterviewLearningContextBuilder()

    init(settingsViewModel: SettingsViewModel, modelContext: ModelContext) {
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
    }

    func load() {
        do {
            let applications = try modelContext.fetch(FetchDescriptor<JobApplication>())
            let context = builder.build(from: applications)
            questionBankEntries = context.questionBankEntries
            fallbackSnapshot = builder.fallbackInsights(from: context)
            snapshot = try latestSnapshot()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
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

        do {
            let applications = try modelContext.fetch(FetchDescriptor<JobApplication>())
            let requestStartedAt = Date()
            isLoading = true
            defer { isLoading = false }

            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await InterviewLearningService.generateSnapshot(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    applications: applications,
                    in: modelContext
                )
            }

            snapshot = result.snapshot
            let context = builder.build(from: applications)
            questionBankEntries = context.questionBankEntries
            fallbackSnapshot = builder.fallbackInsights(from: context)

            _ = try? AIUsageLedgerService.record(
                feature: .interviewLearnings,
                provider: provider,
                model: model,
                usage: result.usage,
                status: .succeeded,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: nil,
                in: modelContext
            )
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            self.error = keyError.localizedDescription
        } catch let aiError as AIServiceError {
            self.error = aiError.localizedDescription
        } catch {
            self.error = "Failed to refresh interview learnings: \(error.localizedDescription)"
        }
    }

    private func latestSnapshot() throws -> InterviewLearningSnapshot? {
        try modelContext.fetch(FetchDescriptor<InterviewLearningSnapshot>())
            .sorted { $0.generatedAt > $1.generatedAt }
            .first
    }
}

@Observable
final class CompanyResearchViewModel {
    var isLoading = false
    var isRefreshingComparison = false
    var error: String?
    var comparison: CompanyCompensationComparisonResult?
    var lastCompletedAt: Date?

    private let application: JobApplication
    private let company: CompanyProfile
    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext?
    private let comparisonService: CompanyCompensationComparisonService

    init(
        application: JobApplication,
        company: CompanyProfile,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext?,
        comparisonService: CompanyCompensationComparisonService = CompanyCompensationComparisonService()
    ) {
        self.application = application
        self.company = company
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
        self.comparisonService = comparisonService
    }

    @MainActor
    func generateResearch() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            error = "No AI model configured. Please check Settings."
            return
        }

        let requestStartedAt = Date()
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            let webContentProvider = WKWebViewContentProvider(serviceName: "CompanyResearch")
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await CompanyResearchService.generateResearch(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    company: company,
                    application: application,
                    webContentProvider: webContentProvider
                )
            }

            let requestStatus = usageStatus(for: result.runStatus)

            if let modelContext {
                _ = try CompanyResearchService.applyResearchResult(
                    result,
                    to: company,
                    provider: provider,
                    model: model,
                    applicationID: application.id,
                    requestStatus: requestStatus,
                    startedAt: requestStartedAt,
                    finishedAt: Date(),
                    in: modelContext
                )

                try ApplicationChecklistService().sync(
                    for: application,
                    trigger: .companyResearchSaved,
                    in: modelContext
                )

                _ = try? AIUsageLedgerService.record(
                    feature: .companyResearch,
                    provider: provider,
                    model: model,
                    usage: result.usage,
                    status: requestStatus,
                    applicationID: application.id,
                    companyID: company.id,
                    startedAt: requestStartedAt,
                    finishedAt: Date(),
                    errorMessage: result.failureMessage,
                    in: modelContext
                )
            }

            lastCompletedAt = Date()
            error = result.runStatus == .failed ? (result.failureMessage ?? "Failed to research company.") : nil
            await refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            error = keyError.localizedDescription
            recordFailure(provider: provider, model: model, startedAt: requestStartedAt, message: keyError.localizedDescription)
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
            recordFailure(provider: provider, model: model, startedAt: requestStartedAt, message: aiError.localizedDescription)
        } catch let unexpectedError {
            error = "Failed to research company: \(unexpectedError.localizedDescription)"
            recordFailure(provider: provider, model: model, startedAt: requestStartedAt, message: unexpectedError.localizedDescription)
        }
    }

    @MainActor
    func refreshComparison(baseCurrency: Currency) async {
        isRefreshingComparison = true
        comparison = await comparisonService.makeComparison(
            for: application,
            company: company,
            baseCurrency: baseCurrency
        )
        isRefreshingComparison = false
    }

    func retryResearch(for _: CompanyResearchSource? = nil) async {
        await generateResearch()
    }

    func setExcluded(_ excluded: Bool, for source: CompanyResearchSource) {
        guard let modelContext else { return }
        source.isExcludedFromResearch = excluded
        source.updateTimestamp()
        do {
            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func useManualNote(for source: CompanyResearchSource) {
        guard let modelContext else { return }

        let template = """
        Manual note for \(source.title)
        URL: \(source.resolvedURLString ?? source.urlString)
        Notes:
        - Add your own findings here.
        """

        let existing = company.notesMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing?.contains(source.urlString) == true {
            return
        }

        company.setNotesMarkdown([existing, template].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n"))
        do {
            try modelContext.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func usageStatus(for runStatus: ResearchRunStatus) -> AIUsageRequestStatus {
        switch runStatus {
        case .succeeded:
            return .succeeded
        case .partial:
            return .partial
        case .failed:
            return .failed
        }
    }

    private func recordFailure(
        provider: AIProvider,
        model: String,
        startedAt: Date,
        message: String
    ) {
        guard let modelContext else { return }
        _ = try? AIUsageLedgerService.record(
            feature: .companyResearch,
            provider: provider,
            model: model,
            usage: nil,
            status: .failed,
            applicationID: application.id,
            companyID: company.id,
            startedAt: startedAt,
            finishedAt: Date(),
            errorMessage: message,
            in: modelContext
        )
    }
}
