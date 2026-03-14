import Foundation
import SwiftUI
import SwiftData
import PipelineKit

@MainActor
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

    @MainActor
    func archive(_ application: JobApplication, context: ModelContext) throws {
        _ = try ApplicationStatusTransitionService.applyStatus(.archived, to: application, in: context)
        Task { @MainActor in
            await NotificationService.shared.syncReminderState(for: application)
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

    @MainActor
    func updateStatus(
        _ status: ApplicationStatus,
        for application: JobApplication,
        context: ModelContext
    ) throws -> StatusTransitionResult {
        let result = try ApplicationStatusTransitionService.applyStatus(status, to: application, in: context)
        Task { @MainActor in
            await NotificationService.shared.syncReminderState(for: application)
        }
        return result
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

    func setApplyQueueMembership(
        _ isQueued: Bool,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        application.setApplyQueue(isQueued)

        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    @discardableResult
    func markAppliedFromQueue(
        for application: JobApplication,
        context: ModelContext
    ) throws -> StatusTransitionResult {
        try updateStatus(.applied, for: application, context: context)
    }

    func updateSeniorityOverride(
        _ seniority: SeniorityBand?,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        let previousSeniority = application.seniorityOverride
        application.setSeniorityOverride(seniority)
        do {
            try context.save()
        } catch {
            application.setSeniorityOverride(previousSeniority, shouldTouch: false)
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
        seniority: SeniorityBand?,
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
                seniority: seniority,
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
                seniority: seniority,
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

        if !(application.followUpSteps?.isEmpty ?? true) {
            try SmartFollowUpService.shared.applyManualFollowUpDate(nil, for: application, in: context)
        } else {
            application.nextFollowUpDate = nil
            application.updateTimestamp()
        }
        ApplicationTimelineRecorderService.recordFollowUpChange(
            for: application,
            from: previousFollowUpDate,
            to: application.nextFollowUpDate,
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

    func markFollowUpStepDone(
        _ step: FollowUpStep,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        let previousFollowUpDate = application.nextFollowUpDate
        try SmartFollowUpService.shared.markStepDone(step, for: application, in: context)
        ApplicationTimelineRecorderService.recordFollowUpChange(
            for: application,
            from: previousFollowUpDate,
            to: application.nextFollowUpDate,
            in: context
        )
    }

    func snoozeFollowUpStep(
        _ step: FollowUpStep,
        by days: Int,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        let previousFollowUpDate = application.nextFollowUpDate
        try SmartFollowUpService.shared.snoozeStep(step, by: days, for: application, in: context)
        ApplicationTimelineRecorderService.recordFollowUpChange(
            for: application,
            from: previousFollowUpDate,
            to: application.nextFollowUpDate,
            in: context
        )
    }

    func dismissFollowUpStep(
        _ step: FollowUpStep,
        for application: JobApplication,
        context: ModelContext
    ) throws {
        let previousFollowUpDate = application.nextFollowUpDate
        try SmartFollowUpService.shared.dismissStep(step, for: application, in: context)
        ApplicationTimelineRecorderService.recordFollowUpChange(
            for: application,
            from: previousFollowUpDate,
            to: application.nextFollowUpDate,
            in: context
        )
    }

    func recordGeneratedFollowUpDraft(
        subject: String?,
        body: String?,
        for step: FollowUpStep,
        application: JobApplication,
        context: ModelContext
    ) throws {
        try SmartFollowUpService.shared.recordGeneratedDraft(
            subject: subject,
            body: body,
            for: step,
            application: application,
            in: context
        )
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
        let previousKind = existingActivity?.kind
        let interviewStateMayHaveChanged = previousKind == .interview || kind == .interview

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
            if interviewStateMayHaveChanged {
                _ = try SmartFollowUpService.shared.refresh(application, in: context)
            }
            try syncChecklist(for: application, trigger: .statusChanged, context: context)
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
                if previousKind == .interview && kind != .interview {
                    await GoogleCalendarInterviewSyncCoordinator.shared.deleteActivity(
                        activity,
                        application: application,
                        in: context
                    )
                } else if kind == .interview {
                    await GoogleCalendarInterviewSyncCoordinator.shared.syncActivity(
                        activity,
                        for: application,
                        in: context
                    )
                }
            }
        } catch {
            context.rollback()
            throw error
        }
    }

    func deleteActivity(_ activity: ApplicationActivity, from application: JobApplication, context: ModelContext) throws {
        guard !activity.isSystemGenerated else { return }
        let interviewStateMayHaveChanged = activity.kind == .interview

        context.delete(activity)
        application.activities?.removeAll(where: { $0.id == activity.id })
        application.updateTimestamp()
        syncInterviewState(for: application, context: context)

        do {
            if interviewStateMayHaveChanged {
                _ = try SmartFollowUpService.shared.refresh(application, in: context)
            }
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
                if activity.kind == .interview {
                    await GoogleCalendarInterviewSyncCoordinator.shared.deleteActivity(
                        activity,
                        application: application,
                        in: context
                    )
                }
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

@MainActor
@Observable
final class ApplicationMarketDataViewModel {
    var isLoading = false
    var isGeneratingNegotiation = false
    var error: String?
    var benchmark: MarketSalaryBenchmarkResult?
    var personalAnalytics: PersonalSalaryAnalyticsResult?
    var negotiationGuidance: ApplicationNegotiationGuidanceOutput?

    private let settingsViewModel: SettingsViewModel
    private let benchmarkService: MarketSalaryBenchmarkService
    private let personalAnalyticsService: PersonalSalaryAnalyticsService

    init(
        settingsViewModel: SettingsViewModel,
        benchmarkService: MarketSalaryBenchmarkService = MarketSalaryBenchmarkService(),
        personalAnalyticsService: PersonalSalaryAnalyticsService = PersonalSalaryAnalyticsService()
    ) {
        self.settingsViewModel = settingsViewModel
        self.benchmarkService = benchmarkService
        self.personalAnalyticsService = personalAnalyticsService
    }

    var aiReady: Bool {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else { return false }
        guard ApplicationNegotiationGuidanceService.isSupported(provider: provider, model: model) else { return false }
        return settingsViewModel.hasAPIKey(for: provider)
    }

    func refresh(
        for application: JobApplication,
        applications: [JobApplication],
        salarySnapshots: [CompanySalarySnapshot],
        baseCurrency: Currency
    ) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        benchmark = await benchmarkService.benchmark(
            for: application,
            among: applications,
            salarySnapshots: salarySnapshots,
            baseCurrency: baseCurrency
        )
        personalAnalytics = await personalAnalyticsService.analyze(
            applications: applications,
            baseCurrency: baseCurrency
        )
        negotiationGuidance = nil
    }

    func generateNegotiation(for application: JobApplication) async {
        guard let benchmark else {
            error = "No market benchmark is available yet for this application."
            return
        }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else {
            error = "Configure an AI model in Settings to generate negotiation guidance."
            return
        }
        guard settingsViewModel.hasAPIKey(for: provider) else {
            error = "Add an API key in Settings to generate negotiation guidance."
            return
        }
        guard ApplicationNegotiationGuidanceService.isSupported(provider: provider, model: model) else {
            error = "The selected model does not support grounded negotiation guidance."
            return
        }

        let snapshots = (application.company?.sortedSalarySnapshots ?? [])
            .filter { snapshot in
                snapshot.matches(roleTitle: application.role, location: application.location)
            }

        isGeneratingNegotiation = true
        defer { isGeneratingNegotiation = false }

        do {
            negotiationGuidance = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await ApplicationNegotiationGuidanceService.generate(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    application: application,
                    benchmark: benchmark,
                    savedSnapshots: snapshots
                )
            }
        } catch let keyError as SettingsViewModel.APIKeyValidationError {
            self.error = keyError.localizedDescription
        } catch let aiError as AIServiceError {
            self.error = aiError.localizedDescription
        } catch {
            self.error = "Failed to generate negotiation guidance: \(error.localizedDescription)"
        }
    }
}

@MainActor
@Observable
final class RejectionLearningsViewModel {
    var isAnalyzing = false
    var error: String?
    var snapshot: RejectionLearningSnapshot?

    private let settingsViewModel: SettingsViewModel
    private let modelContext: ModelContext
    private let builder = RejectionLearningContextBuilder()

    init(settingsViewModel: SettingsViewModel, modelContext: ModelContext) {
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
    }

    var hasConfiguredAI: Bool {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.isEmpty else { return false }
        return settingsViewModel.hasAPIKey(for: provider)
    }

    func load() {
        snapshot = latestSnapshot()
    }

    func refresh() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            error = "Configure an AI model in Settings to analyze rejection patterns."
            return
        }

        guard settingsViewModel.hasAPIKey(for: provider) else {
            error = "Add an API key in Settings to analyze rejection patterns."
            return
        }

        do {
            let applications = try modelContext.fetch(FetchDescriptor<JobApplication>())
            let context = builder.build(from: applications)
            guard context.rejectionCount >= 3 else {
                error = "Log at least 3 rejections before running rejection analysis."
                snapshot = latestSnapshot()
                return
            }

            let requestStartedAt = Date()
            isAnalyzing = true
            defer { isAnalyzing = false }

            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await RejectionLearningService.generateSnapshot(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    applications: applications,
                    in: modelContext
                )
            }

            snapshot = result.snapshot
            _ = try? AIUsageLedgerService.record(
                feature: .rejectionLearnings,
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
            error = keyError.localizedDescription
        } catch let aiError as AIServiceError {
            error = aiError.localizedDescription
        } catch let unexpectedError {
            error = "Failed to analyze rejection patterns: \(unexpectedError.localizedDescription)"
        }
    }

    private func latestSnapshot() -> RejectionLearningSnapshot? {
        ((try? modelContext.fetch(FetchDescriptor<RejectionLearningSnapshot>())) ?? [])
            .sorted { $0.generatedAt > $1.generatedAt }
            .first
    }
}

@MainActor
@Observable
final class RejectionLogEditorViewModel {
    var stageCategory: RejectionStageCategory
    var reasonCategory: RejectionReasonCategory
    var feedbackSource: RejectionFeedbackSource
    var feedbackText: String
    var candidateReflection: String
    var doNotReapply: Bool
    var isSaving = false
    var errorMessage: String?
    var postSaveWarning: String?

    private let activity: ApplicationActivity
    private let application: JobApplication
    private let modelContext: ModelContext
    private let settingsViewModel: SettingsViewModel
    private let builder = RejectionLearningContextBuilder()

    init(
        activity: ApplicationActivity,
        application: JobApplication,
        modelContext: ModelContext,
        settingsViewModel: SettingsViewModel
    ) {
        self.activity = activity
        self.application = application
        self.modelContext = modelContext
        self.settingsViewModel = settingsViewModel

        if let log = activity.rejectionLog {
            self.stageCategory = log.stageCategory
            self.reasonCategory = log.reasonCategory
            self.feedbackSource = log.feedbackSource
            self.feedbackText = log.feedbackText ?? ""
            self.candidateReflection = log.candidateReflection ?? ""
            self.doNotReapply = log.doNotReapply
        } else {
            self.stageCategory = Self.defaultStageCategory(for: application, activity: activity)
            self.reasonCategory = .unknown
            self.feedbackSource = .none
            self.feedbackText = ""
            self.candidateReflection = ""
            self.doNotReapply = false
        }
    }

    func save() async throws {
        guard activity.isRejectionStatusChange else {
            throw SaveError.invalidActivity
        }

        isSaving = true
        defer { isSaving = false }
        postSaveWarning = nil

        let log: RejectionLog
        if let existing = activity.rejectionLog {
            log = existing
        } else {
            log = RejectionLog(activity: activity)
            modelContext.insert(log)
            activity.rejectionLog = log
        }

        log.update(
            stageCategory: stageCategory,
            reasonCategory: reasonCategory,
            feedbackSource: feedbackSource,
            feedbackText: normalized(feedbackText),
            candidateReflection: normalized(candidateReflection),
            doNotReapply: doNotReapply
        )
        activity.updateTimestamp()
        application.updateTimestamp()
        try modelContext.save()

        await refreshLearningsIfPossible()
    }

    private func refreshLearningsIfPossible() async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty, settingsViewModel.hasAPIKey(for: provider) else { return }

        let applications = ((try? modelContext.fetch(FetchDescriptor<JobApplication>())) ?? [])
        let context = builder.build(from: applications)
        guard context.rejectionCount >= 3 else { return }

        let requestStartedAt = Date()

        do {
            let result = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await RejectionLearningService.generateSnapshot(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    applications: applications,
                    in: modelContext
                )
            }

            _ = result
            _ = try? AIUsageLedgerService.record(
                feature: .rejectionLearnings,
                provider: provider,
                model: model,
                usage: result.usage,
                status: .succeeded,
                applicationID: application.id,
                startedAt: requestStartedAt,
                finishedAt: Date(),
                errorMessage: nil,
                in: modelContext
            )
        } catch {
            postSaveWarning = "The rejection log was saved, but Pipeline could not refresh rejection learnings."
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func defaultStageCategory(
        for application: JobApplication,
        activity: ApplicationActivity
    ) -> RejectionStageCategory {
        if let interviewStage = activity.interviewStage
            ?? application.latestRejectionActivity?.interviewStage
            ?? application.latestInterviewActivity?.interviewStage
            ?? application.interviewStage {
            switch interviewStage {
            case .phoneScreen, .hrRound:
                return .phoneScreen
            case .technicalRound1, .technicalRound2, .designChallenge, .systemDesign:
                return .technical
            case .finalRound:
                return .final
            case .offerExtended:
                return .offerStage
            case .custom:
                return .unknown
            }
        }

        if application.appliedDate != nil {
            return .preScreen
        }

        return .unknown
    }

    enum SaveError: LocalizedError {
        case invalidActivity

        var errorDescription: String? {
            switch self {
            case .invalidActivity:
                return "Pipeline can only save rejection logs on rejected status changes."
            }
        }
    }
}

struct ApplyQueuePreparationResult: Identifiable {
    let applicationID: UUID
    let completedSteps: [ApplyQueuePreparationStep]
    let failedSteps: [ApplyQueuePreparationStep]
    let messages: [String]

    var id: UUID { applicationID }
}

enum ApplyQueuePreparationStep: String, CaseIterable, Sendable {
    case resumeTailoring
    case coverLetter
    case companyResearch

    var title: String {
        switch self {
        case .resumeTailoring:
            return "Tailored resume"
        case .coverLetter:
            return "Cover letter"
        case .companyResearch:
            return "Company research"
        }
    }
}

@MainActor
final class ApplyQueuePreparationCoordinator {
    static let shared = ApplyQueuePreparationCoordinator()

    private init() {}

    func prepare(
        applications: [JobApplication],
        modelContext: ModelContext,
        settingsViewModel: SettingsViewModel,
        concurrencyLimit: Int = 2
    ) async -> [ApplyQueuePreparationResult] {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedModel.isEmpty else {
            let message = "No AI model configured. Please check Settings."
            return applications.map {
                ApplyQueuePreparationResult(
                    applicationID: $0.id,
                    completedSteps: [],
                    failedSteps: missingPreparationSteps(for: $0),
                    messages: [message]
                )
            }
        }

        let apiKey: String
        do {
            guard let firstKey = try settingsViewModel.apiKeys(for: provider).first,
                  !firstKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                let message = "API key not configured for \(provider.rawValue). Please check Settings."
                return applications.map {
                    ApplyQueuePreparationResult(
                        applicationID: $0.id,
                        completedSteps: [],
                        failedSteps: missingPreparationSteps(for: $0),
                        messages: [message]
                    )
                }
            }
            apiKey = firstKey
        } catch {
            let message = "Could not access API key. Please check Settings."
            return applications.map {
                ApplyQueuePreparationResult(
                    applicationID: $0.id,
                    completedSteps: [],
                    failedSteps: missingPreparationSteps(for: $0),
                    messages: [message]
                )
            }
        }

        let masterRevision = try? ResumeStoreService.currentMasterRevision(in: modelContext)
        let inputs = applications.map {
            makePreparationInput(
                for: $0,
                modelContext: modelContext,
                provider: provider,
                model: trimmedModel,
                apiKey: apiKey,
                masterRevision: masterRevision
            )
        }

        let chunkSize = max(1, concurrencyLimit)
        var preparedResults: [ApplyQueuePreparationResult] = []

        for startIndex in stride(from: 0, to: inputs.count, by: chunkSize) {
            let chunk = Array(inputs[startIndex..<min(startIndex + chunkSize, inputs.count)])
            let payloads = await withTaskGroup(of: ApplyQueuePreparationPayload.self) { group in
                for input in chunk {
                    group.addTask {
                        await Self.preparePayload(for: input)
                    }
                }

                var collected: [ApplyQueuePreparationPayload] = []
                for await payload in group {
                    collected.append(payload)
                }
                return collected
            }

            for payload in payloads {
                preparedResults.append(
                    await persist(
                        payload: payload,
                        applications: applications,
                        modelContext: modelContext
                    )
                )
            }
        }

        return preparedResults
    }

    private func makePreparationInput(
        for application: JobApplication,
        modelContext: ModelContext,
        provider: AIProvider,
        model: String,
        apiKey: String,
        masterRevision: ResumeMasterRevision?
    ) -> ApplyQueuePreparationInput {
        let preferredResumeSource = try? ResumeStoreService.preferredResumeSource(
            for: application,
            in: modelContext
        )
        let prepStatus = SavedApplicationPreparationService.status(for: application)

        return ApplyQueuePreparationInput(
            applicationID: application.id,
            companyName: application.companyName,
            role: application.role,
            location: application.location,
            jobURL: application.jobURL,
            jobDescription: application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
            notesContext: coverLetterNotesContext(for: application),
            companySeed: CompanySeed(
                name: application.company?.name ?? application.companyName,
                websiteURL: application.company?.websiteURL,
                linkedInURL: application.company?.linkedInURL,
                glassdoorURL: application.company?.glassdoorURL,
                levelsFYIURL: application.company?.levelsFYIURL,
                teamBlindURL: application.company?.teamBlindURL,
                industry: application.company?.industry,
                sizeBand: application.company?.sizeBand,
                headquarters: application.company?.headquarters
            ),
            preparationStatus: prepStatus,
            provider: provider,
            model: model,
            apiKey: apiKey,
            masterResumeJSON: masterRevision?.rawJSON,
            masterRevisionID: masterRevision?.id,
            existingResumeSource: preferredResumeSource
        )
    }

    private func persist(
        payload: ApplyQueuePreparationPayload,
        applications: [JobApplication],
        modelContext: ModelContext
    ) async -> ApplyQueuePreparationResult {
        guard let application = applications.first(where: { $0.id == payload.applicationID }) else {
            return ApplyQueuePreparationResult(
                applicationID: payload.applicationID,
                completedSteps: [],
                failedSteps: Array(payload.failures.keys).sorted(by: sortSteps),
                messages: Array(Set(payload.failures.values)).sorted()
            )
        }

        var completedSteps = payload.completedSteps
        var failures = payload.failures
        var coverLetterSource = payload.coverLetterSource

        if let resumePayload = payload.resumeSnapshot {
            do {
                let snapshot = try ResumeStoreService.createJobSnapshot(
                    for: application,
                    rawJSON: resumePayload.rawJSON,
                    acceptedPatchIDs: resumePayload.acceptedPatchIDs,
                    rejectedPatchIDs: [],
                    sectionGaps: resumePayload.sectionGaps,
                    sourceMasterRevisionID: resumePayload.sourceMasterRevisionID,
                    in: modelContext
                )
                await ATSCompatibilityCoordinator.shared.refresh(
                    application: application,
                    modelContext: modelContext,
                    force: true,
                    trigger: .autoSnapshot
                )
                coverLetterSource = ResumeSourceSelection(
                    kind: .tailoredSnapshot,
                    rawJSON: resumePayload.rawJSON,
                    snapshotID: snapshot.id,
                    masterRevisionID: resumePayload.sourceMasterRevisionID,
                    createdAt: snapshot.createdAt
                )
                recordUsage(
                    feature: .resumeTailoring,
                    provider: payload.provider,
                    model: payload.model,
                    usage: resumePayload.usage,
                    applicationID: application.id,
                    in: modelContext
                )
            } catch {
                completedSteps.removeAll(where: { $0 == .resumeTailoring })
                failures[.resumeTailoring] = error.localizedDescription
            }
        }

        if let coverLetter = payload.coverLetter {
            do {
                try persistCoverLetter(
                    result: coverLetter,
                    source: coverLetterSource,
                    provider: payload.provider,
                    model: payload.model,
                    application: application,
                    modelContext: modelContext
                )
                recordUsage(
                    feature: .coverLetterDraft,
                    provider: payload.provider,
                    model: payload.model,
                    usage: coverLetter.usage,
                    applicationID: application.id,
                    in: modelContext
                )
            } catch {
                completedSteps.removeAll(where: { $0 == .coverLetter })
                failures[.coverLetter] = error.localizedDescription
            }
        }

        if let research = payload.companyResearch {
            do {
                let company = try CompanyLinkingService.ensureCompanyLinked(for: application, in: modelContext)
                let requestStatus = usageStatus(for: research.runStatus)
                _ = try CompanyResearchService.applyResearchResult(
                    research,
                    to: company,
                    provider: payload.provider,
                    model: payload.model,
                    applicationID: application.id,
                    requestStatus: requestStatus,
                    startedAt: payload.requestStartedAt,
                    finishedAt: Date(),
                    in: modelContext
                )
                try ApplicationChecklistService().sync(
                    for: application,
                    trigger: .companyResearchSaved,
                    in: modelContext
                )
                recordUsage(
                    feature: .companyResearch,
                    provider: payload.provider,
                    model: payload.model,
                    usage: research.usage,
                    applicationID: application.id,
                    companyID: company.id,
                    requestStatus: requestStatus,
                    errorMessage: research.failureMessage,
                    in: modelContext
                )
                if research.runStatus == .failed {
                    completedSteps.removeAll(where: { $0 == .companyResearch })
                    failures[.companyResearch] = research.failureMessage ?? "Failed to research company."
                }
            } catch {
                completedSteps.removeAll(where: { $0 == .companyResearch })
                failures[.companyResearch] = error.localizedDescription
            }
        }

        return ApplyQueuePreparationResult(
            applicationID: application.id,
            completedSteps: completedSteps.sorted(by: sortSteps),
            failedSteps: Array(failures.keys).sorted(by: sortSteps),
            messages: Array(Set(failures.values)).sorted()
        )
    }

    private func persistCoverLetter(
        result: CoverLetterGenerationResult,
        source: ResumeSourceSelection?,
        provider: AIProvider,
        model: String,
        application: JobApplication,
        modelContext: ModelContext
    ) throws {
        let draft: CoverLetterDraft
        if let existingDraft = application.coverLetterDraft {
            draft = existingDraft
        } else {
            let newDraft = CoverLetterDraft(tone: .formal)
            newDraft.application = application
            application.assignCoverLetterDraft(newDraft)
            modelContext.insert(newDraft)
            draft = newDraft
        }

        draft.applyEdits(
            tone: .formal,
            greeting: result.greeting,
            hookParagraph: result.hookParagraph,
            bodyParagraphs: result.bodyParagraphs,
            closingParagraph: result.closingParagraph,
            shouldTouch: false
        )
        draft.recordGenerationMetadata(
            sourceResumeKind: source?.kind.rawValue,
            sourceResumeLabel: source?.label,
            sourceResumeSnapshotID: source?.snapshotID,
            providerID: provider.providerID,
            model: model,
            generatedAt: Date(),
            shouldTouch: false
        )
        draft.refreshPlainText(shouldTouch: false)
        draft.updateTimestamp()
        application.updateTimestamp()
        try ApplicationChecklistService().sync(
            for: application,
            trigger: .coverLetterSaved,
            in: modelContext
        )
    }

    private func recordUsage(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        applicationID: UUID,
        companyID: UUID? = nil,
        requestStatus: AIUsageRequestStatus = .succeeded,
        errorMessage: String? = nil,
        in modelContext: ModelContext
    ) {
        _ = try? AIUsageLedgerService.record(
            feature: feature,
            provider: provider,
            model: model,
            usage: usage,
            status: requestStatus,
            applicationID: applicationID,
            companyID: companyID,
            startedAt: Date(),
            finishedAt: Date(),
            errorMessage: errorMessage,
            in: modelContext
        )
    }

    private func missingPreparationSteps(for application: JobApplication) -> [ApplyQueuePreparationStep] {
        let prepStatus = SavedApplicationPreparationService.status(for: application)
        var steps: [ApplyQueuePreparationStep] = []
        if !prepStatus.hasTailoredResume {
            steps.append(.resumeTailoring)
        }
        if !prepStatus.hasCoverLetter {
            steps.append(.coverLetter)
        }
        if !prepStatus.hasCompanyResearch {
            steps.append(.companyResearch)
        }
        return steps
    }

    private func coverLetterNotesContext(for application: JobApplication) -> String {
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

    private func sortSteps(_ lhs: ApplyQueuePreparationStep, _ rhs: ApplyQueuePreparationStep) -> Bool {
        ApplyQueuePreparationStep.allCases.firstIndex(of: lhs) ?? 0 < ApplyQueuePreparationStep.allCases.firstIndex(of: rhs) ?? 0
    }

    private static func preparePayload(for input: ApplyQueuePreparationInput) async -> ApplyQueuePreparationPayload {
        var completedSteps: [ApplyQueuePreparationStep] = []
        var failures: [ApplyQueuePreparationStep: String] = [:]
        var preparedResumeSnapshot: PreparedResumeSnapshot?
        var coverLetterResult: CoverLetterGenerationResult?
        var companyResearchResult: CompanyResearchResult?
        var coverLetterSource = input.existingResumeSource

        if !input.preparationStatus.hasTailoredResume {
            if let masterResumeJSON = input.masterResumeJSON,
               let jobDescription = input.jobDescription,
               !jobDescription.isEmpty {
                do {
                    let result = try await ResumeTailoringService.generateSuggestions(
                        provider: input.provider,
                        apiKey: input.apiKey,
                        model: input.model,
                        resumeJSON: masterResumeJSON,
                        company: input.companyName,
                        role: input.role,
                        jobDescription: jobDescription
                    )
                    let acceptedPatchIDs = Array(result.patches.map(\.id))
                    let normalizedJSON = try ResumePatchApplier.apply(
                        patches: result.patches,
                        acceptedPatchIDs: Set(acceptedPatchIDs),
                        to: masterResumeJSON
                    )
                    let validated = try ResumeSchemaValidator.validate(jsonText: normalizedJSON)
                    preparedResumeSnapshot = PreparedResumeSnapshot(
                        rawJSON: validated.normalizedJSON,
                        acceptedPatchIDs: acceptedPatchIDs,
                        sectionGaps: result.sectionGaps,
                        sourceMasterRevisionID: input.masterRevisionID,
                        usage: result.usage
                    )
                    coverLetterSource = ResumeSourceSelection(
                        kind: .tailoredSnapshot,
                        rawJSON: validated.normalizedJSON,
                        snapshotID: nil,
                        masterRevisionID: input.masterRevisionID,
                        createdAt: Date()
                    )
                    completedSteps.append(.resumeTailoring)
                } catch {
                    failures[.resumeTailoring] = error.localizedDescription
                }
            } else if input.masterResumeJSON == nil {
                failures[.resumeTailoring] = "Save a master resume before batch prep can tailor applications."
            } else {
                failures[.resumeTailoring] = "This job is missing a job description."
            }
        }

        if !input.preparationStatus.hasCoverLetter {
            if let jobDescription = input.jobDescription,
               !jobDescription.isEmpty,
               let coverLetterSource {
                do {
                    coverLetterResult = try await CoverLetterGenerationService.generateCoverLetter(
                        provider: input.provider,
                        apiKey: input.apiKey,
                        model: input.model,
                        tone: .formal,
                        company: input.companyName,
                        role: input.role,
                        jobDescription: jobDescription,
                        notes: input.notesContext,
                        resumeJSON: coverLetterSource.rawJSON
                    )
                    completedSteps.append(.coverLetter)
                } catch {
                    failures[.coverLetter] = error.localizedDescription
                }
            } else if input.jobDescription?.isEmpty != false {
                failures[.coverLetter] = "This job is missing a job description."
            } else {
                failures[.coverLetter] = "Save a master resume or tailored resume before generating a cover letter."
            }
        }

        if !input.preparationStatus.hasCompanyResearch {
            do {
                let company = input.companySeed.makeCompanyProfile()
                let application = JobApplication(
                    companyName: input.companyName,
                    role: input.role,
                    location: input.location,
                    jobURL: input.jobURL,
                    jobDescription: input.jobDescription,
                    company: company
                )
                companyResearchResult = try await CompanyResearchService.generateResearch(
                    provider: input.provider,
                    apiKey: input.apiKey,
                    model: input.model,
                    company: company,
                    application: application
                )
                completedSteps.append(.companyResearch)
            } catch {
                failures[.companyResearch] = error.localizedDescription
            }
        }

        return ApplyQueuePreparationPayload(
            applicationID: input.applicationID,
            provider: input.provider,
            model: input.model,
            requestStartedAt: Date(),
            completedSteps: completedSteps,
            failures: failures,
            resumeSnapshot: preparedResumeSnapshot,
            coverLetter: coverLetterResult,
            coverLetterSource: coverLetterSource,
            companyResearch: companyResearchResult
        )
    }
}

private struct ApplyQueuePreparationInput: Sendable {
    let applicationID: UUID
    let companyName: String
    let role: String
    let location: String
    let jobURL: String?
    let jobDescription: String?
    let notesContext: String
    let companySeed: CompanySeed
    let preparationStatus: SavedApplicationPreparationStatus
    let provider: AIProvider
    let model: String
    let apiKey: String
    let masterResumeJSON: String?
    let masterRevisionID: UUID?
    let existingResumeSource: ResumeSourceSelection?
}

private struct ApplyQueuePreparationPayload: Sendable {
    let applicationID: UUID
    let provider: AIProvider
    let model: String
    let requestStartedAt: Date
    let completedSteps: [ApplyQueuePreparationStep]
    let failures: [ApplyQueuePreparationStep: String]
    let resumeSnapshot: PreparedResumeSnapshot?
    let coverLetter: CoverLetterGenerationResult?
    let coverLetterSource: ResumeSourceSelection?
    let companyResearch: CompanyResearchResult?
}

private struct PreparedResumeSnapshot: Sendable {
    let rawJSON: String
    let acceptedPatchIDs: [UUID]
    let sectionGaps: [String]
    let sourceMasterRevisionID: UUID?
    let usage: AIUsageMetrics?
}

private struct CompanySeed: Sendable {
    let name: String
    let websiteURL: String?
    let linkedInURL: String?
    let glassdoorURL: String?
    let levelsFYIURL: String?
    let teamBlindURL: String?
    let industry: String?
    let sizeBand: CompanySizeBand?
    let headquarters: String?

    func makeCompanyProfile() -> CompanyProfile {
        CompanyProfile(
            name: name,
            websiteURL: websiteURL,
            linkedInURL: linkedInURL,
            glassdoorURL: glassdoorURL,
            levelsFYIURL: levelsFYIURL,
            teamBlindURL: teamBlindURL,
            industry: industry,
            sizeBand: sizeBand,
            headquarters: headquarters
        )
    }
}

private extension JobApplication {
    var latestInterviewActivity: ApplicationActivity? {
        sortedInterviewActivities.first
    }
}
