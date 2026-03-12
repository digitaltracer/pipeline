import Foundation
import SwiftData

@Model
public final class WeeklyDigestSnapshot {
    public var id: UUID = UUID()
    public var weekStart: Date = Date()
    public var weekEnd: Date = Date()
    public var generatedAt: Date = Date()
    public var notificationDeliveredAt: Date?

    public var newApplicationsCount: Int = 0
    public var newApplicationsDelta: Int = 0
    public var responseRate: Double = 0
    public var previousResponseRate: Double = 0
    public var interviewsCompletedCount: Int = 0
    public var interviewsScheduledCount: Int = 0
    public var followUpsDueCount: Int = 0
    public var overdueFollowUpsCount: Int = 0
    public var averageMatchScore: Double?
    public var previousAverageMatchScore: Double?
    public var needsTailoringCount: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \WeeklyDigestInsight.snapshot)
    public var insights: [WeeklyDigestInsight]?

    @Relationship(deleteRule: .cascade, inverse: \WeeklyDigestActionItem.snapshot)
    public var actionItems: [WeeklyDigestActionItem]?

    public init(
        id: UUID = UUID(),
        weekStart: Date,
        weekEnd: Date,
        generatedAt: Date = Date(),
        notificationDeliveredAt: Date? = nil,
        newApplicationsCount: Int,
        newApplicationsDelta: Int,
        responseRate: Double,
        previousResponseRate: Double,
        interviewsCompletedCount: Int,
        interviewsScheduledCount: Int,
        followUpsDueCount: Int,
        overdueFollowUpsCount: Int,
        averageMatchScore: Double?,
        previousAverageMatchScore: Double?,
        needsTailoringCount: Int,
        insights: [WeeklyDigestInsight]? = nil,
        actionItems: [WeeklyDigestActionItem]? = nil
    ) {
        self.id = id
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.generatedAt = generatedAt
        self.notificationDeliveredAt = notificationDeliveredAt
        self.newApplicationsCount = newApplicationsCount
        self.newApplicationsDelta = newApplicationsDelta
        self.responseRate = responseRate
        self.previousResponseRate = previousResponseRate
        self.interviewsCompletedCount = interviewsCompletedCount
        self.interviewsScheduledCount = interviewsScheduledCount
        self.followUpsDueCount = followUpsDueCount
        self.overdueFollowUpsCount = overdueFollowUpsCount
        self.averageMatchScore = averageMatchScore
        self.previousAverageMatchScore = previousAverageMatchScore
        self.needsTailoringCount = needsTailoringCount
        self.insights = insights
        self.actionItems = actionItems
    }

    public var sortedInsights: [WeeklyDigestInsight] {
        (insights ?? []).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public var sortedActionItems: [WeeklyDigestActionItem] {
        (actionItems ?? []).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public var responseRateDelta: Double {
        responseRate - previousResponseRate
    }

    public var matchScoreDelta: Double? {
        guard let averageMatchScore, let previousAverageMatchScore else { return nil }
        return averageMatchScore - previousAverageMatchScore
    }

    public var hasDeliveredNotification: Bool {
        notificationDeliveredAt != nil
    }
}
