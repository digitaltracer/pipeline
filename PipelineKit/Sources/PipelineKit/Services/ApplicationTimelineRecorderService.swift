import Foundation
import SwiftData

public enum ApplicationTimelineRecorderService {
    @discardableResult
    public static func recordStatusChange(
        for application: JobApplication,
        from previousStatus: ApplicationStatus?,
        to newStatus: ApplicationStatus,
        occurredAt: Date = Date(),
        in context: ModelContext
    ) -> ApplicationActivity? {
        guard previousStatus != newStatus else { return nil }

        let activity = ApplicationActivity(
            kind: .statusChange,
            occurredAt: occurredAt,
            application: application,
            interviewStage: newStatus == .rejected ? application.interviewStage : nil,
            fromStatus: previousStatus,
            toStatus: newStatus,
            isSystemGenerated: true
        )
        context.insert(activity)
        application.addActivity(activity)
        return activity
    }

    @discardableResult
    public static func recordFollowUpChange(
        for application: JobApplication,
        from previousDate: Date?,
        to newDate: Date?,
        occurredAt: Date = Date(),
        in context: ModelContext
    ) -> ApplicationActivity? {
        guard previousDate != newDate else { return nil }

        let activity = ApplicationActivity(
            kind: .followUp,
            occurredAt: occurredAt,
            application: application,
            fromFollowUpDate: previousDate,
            toFollowUpDate: newDate,
            isSystemGenerated: true
        )
        context.insert(activity)
        application.addActivity(activity)
        return activity
    }

    public static func seedInitialHistory(
        for application: JobApplication,
        occurredAt: Date = Date(),
        in context: ModelContext
    ) {
        if application.status != .saved {
            recordStatusChange(
                for: application,
                from: nil,
                to: application.status,
                occurredAt: occurredAt,
                in: context
            )
        }

        if application.nextFollowUpDate != nil {
            recordFollowUpChange(
                for: application,
                from: nil,
                to: application.nextFollowUpDate,
                occurredAt: occurredAt,
                in: context
            )
        }
    }
}
