import Foundation
import SwiftData
import PipelineKit

@Observable
final class KanbanViewModel {
    static let columns: [ApplicationStatus] = [
        .saved, .applied, .interviewing, .offered, .rejected
    ]

    func applicationsForColumn(_ status: ApplicationStatus, from applications: [JobApplication]) -> [JobApplication] {
        applications
            .filter { $0.status == status }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func moveApplication(_ application: JobApplication, to status: ApplicationStatus, context: ModelContext) {
        let oldStatus = application.status
        guard oldStatus != status else { return }
        let checklistService = ApplicationChecklistService()

        application.status = status

        // Auto-set appliedDate when moving to Applied or beyond
        if application.appliedDate == nil,
           [.applied, .interviewing, .offered].contains(where: { $0 == status }) {
            application.appliedDate = Date()
        }

        application.updateTimestamp()
        ApplicationTimelineRecorderService.recordStatusChange(
            for: application,
            from: oldStatus,
            to: application.status,
            in: context
        )

        do {
            try checklistService.sync(for: application, trigger: .statusChanged, in: context)
            Task { @MainActor in
                await NotificationService.shared.syncReminderState(for: application)
            }
        } catch {
            context.rollback()
            print("KanbanViewModel: failed to save after move: \(error)")
        }
    }
}
