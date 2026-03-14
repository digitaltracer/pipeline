import Foundation
import SwiftData

public struct StatusTransitionResult: Sendable {
    public let didChange: Bool
    public let statusActivityID: UUID?
    public let needsRejectionLogPrompt: Bool

    public init(
        didChange: Bool,
        statusActivityID: UUID? = nil,
        needsRejectionLogPrompt: Bool = false
    ) {
        self.didChange = didChange
        self.statusActivityID = statusActivityID
        self.needsRejectionLogPrompt = needsRejectionLogPrompt
    }
}

@MainActor
public enum ApplicationStatusTransitionService {
    public static func applyStatus(
        _ status: ApplicationStatus,
        to application: JobApplication,
        occurredAt: Date = Date(),
        in context: ModelContext
    ) throws -> StatusTransitionResult {
        let previousStatus = application.status
        guard previousStatus != status else {
            return StatusTransitionResult(didChange: false)
        }

        application.status = status
        application.updateTimestamp()

        if status != .saved {
            application.setApplyQueue(false, shouldTouch: false)
        }

        if status == .interviewing && application.appliedDate == nil {
            application.appliedDate = occurredAt
        }

        if status == .applied && application.appliedDate == nil {
            application.appliedDate = occurredAt
        }

        let activity = ApplicationTimelineRecorderService.recordStatusChange(
            for: application,
            from: previousStatus,
            to: application.status,
            occurredAt: occurredAt,
            in: context
        )

        do {
            try ApplicationChecklistService().sync(for: application, trigger: .statusChanged, in: context)
            if status == .applied {
                try SmartFollowUpService.shared.ensureAppliedCadence(for: application, in: context)
            } else {
                _ = try SmartFollowUpService.shared.refresh(application, in: context)
                if context.hasChanges {
                    try context.save()
                }
            }
        } catch {
            context.rollback()
            throw error
        }

        return StatusTransitionResult(
            didChange: true,
            statusActivityID: activity?.id,
            needsRejectionLogPrompt: status == .rejected && activity?.needsRejectionLog == true
        )
    }
}
