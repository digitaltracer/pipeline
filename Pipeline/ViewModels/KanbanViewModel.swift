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

    @MainActor
    func moveApplication(
        _ application: JobApplication,
        to status: ApplicationStatus,
        context: ModelContext
    ) throws -> StatusTransitionResult {
        let result = try ApplicationStatusTransitionService.applyStatus(status, to: application, in: context)
        Task { @MainActor in
            await NotificationService.shared.syncReminderState(for: application)
        }
        return result
    }
}
