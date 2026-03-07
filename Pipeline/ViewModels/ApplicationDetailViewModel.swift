import Foundation
import SwiftData
import PipelineKit

@Observable
final class ApplicationDetailViewModel {
    enum SaveValidationError: LocalizedError {
        case emptyActivity
        case emptyTaskTitle

        var errorDescription: String? {
            switch self {
            case .emptyActivity:
                return "Add some notes or activity details before saving."
            case .emptyTaskTitle:
                return "Enter a task title before saving."
            }
        }
    }

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
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
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
            try context.save()
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
            try context.save()
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
            try context.save()
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
            try context.save()
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
            try context.save()
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
}
