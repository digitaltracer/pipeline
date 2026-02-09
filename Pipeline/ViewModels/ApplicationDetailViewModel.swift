import Foundation
import SwiftData

@Observable
final class ApplicationDetailViewModel {
    // MARK: - Actions

    func archive(_ application: JobApplication, context: ModelContext) throws {
        let previousStatus = application.status
        application.status = .archived
        application.updateTimestamp()

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
            }
        } catch {
            application.status = previousStatus
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
        let previousAppliedDate = application.appliedDate
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

        do {
            try context.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
            }
        } catch {
            application.status = previousStatus
            application.appliedDate = previousAppliedDate
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
            application.status = .interviewing
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
}
