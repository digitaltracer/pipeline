import Foundation
import SwiftData
import SwiftUI

@Observable
final class ApplicationDetailViewModel {
    var application: JobApplication?
    var isEditing = false
    var showingAddInterviewLog = false
    var showingDeleteConfirmation = false

    // MARK: - Actions

    func archive(context: ModelContext) {
        guard let application = application else { return }
        application.status = .archived
        application.updateTimestamp()
        try? context.save()
    }

    func delete(context: ModelContext) {
        guard let application = application else { return }
        context.delete(application)
        try? context.save()
        self.application = nil
    }

    func updateStatus(_ status: ApplicationStatus, context: ModelContext) {
        guard let application = application else { return }
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

        try? context.save()
    }

    func updateInterviewStage(_ stage: InterviewStage?, context: ModelContext) {
        guard let application = application else { return }
        application.interviewStage = stage
        application.updateTimestamp()
        try? context.save()
    }

    func updatePriority(_ priority: Priority, context: ModelContext) {
        guard let application = application else { return }
        application.priority = priority
        application.updateTimestamp()
        try? context.save()
    }

    func addInterviewLog(_ log: InterviewLog, context: ModelContext) {
        guard let application = application else { return }
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

        try? context.save()
    }

    func deleteInterviewLog(_ log: InterviewLog, context: ModelContext) {
        context.delete(log)
        application?.updateTimestamp()
        try? context.save()
    }

    // MARK: - Computed Properties

    var canEdit: Bool {
        application != nil
    }

    var canArchive: Bool {
        guard let app = application else { return false }
        return app.status != .archived
    }

    var hasJobURL: Bool {
        guard let app = application else { return false }
        return app.jobURL != nil && !app.jobURL!.isEmpty
    }

    var jobURL: URL? {
        guard let urlString = application?.jobURL else { return nil }
        return URL(string: urlString)
    }
}
