import Foundation
import SwiftData

@Model
public final class JobSearchCycle {
    public var id: UUID = UUID()
    public var name: String = ""
    public var startDate: Date = Date()
    public var endDate: Date?
    public var isActive: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var applications: [JobApplication]?

    public var goals: [SearchGoal]?

    public init(
        id: UUID = UUID(),
        name: String,
        startDate: Date = Date(),
        endDate: Date? = nil,
        isActive: Bool = false,
        applications: [JobApplication]? = nil,
        goals: [SearchGoal]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isActive = isActive
        self.applications = applications
        self.goals = goals
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sortedApplications: [JobApplication] {
        (applications ?? []).sorted { lhs, rhs in
            let lhsDate = lhs.appliedDate ?? lhs.createdAt
            let rhsDate = rhs.appliedDate ?? rhs.createdAt
            if lhsDate == rhsDate {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsDate > rhsDate
        }
    }

    public var sortedGoals: [SearchGoal] {
        (goals ?? []).sorted { lhs, rhs in
            if lhs.isArchived != rhs.isArchived {
                return !lhs.isArchived && rhs.isArchived
            }

            if lhs.cadence != rhs.cadence {
                return lhs.cadence == .weekly && rhs.cadence == .monthly
            }

            if lhs.metric != rhs.metric {
                return lhs.metric.displayName.localizedCaseInsensitiveCompare(rhs.metric.displayName) == .orderedAscending
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    public func activate() {
        isActive = true
        endDate = nil
        updateTimestamp()
    }

    public func end(on date: Date = Date()) {
        endDate = date
        isActive = false
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
