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

        application.status = status

        // Auto-set appliedDate when moving to Applied or beyond
        if application.appliedDate == nil,
           [.applied, .interviewing, .offered].contains(where: { $0 == status }) {
            application.appliedDate = Date()
        }

        application.updateTimestamp()

        do {
            try context.save()
        } catch {
            print("KanbanViewModel: failed to save after move: \(error)")
        }
    }
}
