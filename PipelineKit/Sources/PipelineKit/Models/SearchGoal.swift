import Foundation
import SwiftData

@Model
public final class SearchGoal {
    public var id: UUID = UUID()
    private var metricRawValue: String = SearchGoalMetric.applicationsSubmitted.rawValue
    private var cadenceRawValue: String = SearchGoalCadence.weekly.rawValue
    public var targetValue: Int = 0
    public var isArchived: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var cycle: JobSearchCycle?

    public var metric: SearchGoalMetric {
        get { SearchGoalMetric(rawValue: metricRawValue) ?? .applicationsSubmitted }
        set {
            metricRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var cadence: SearchGoalCadence {
        get { SearchGoalCadence(rawValue: cadenceRawValue) ?? .weekly }
        set {
            cadenceRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public init(
        id: UUID = UUID(),
        metric: SearchGoalMetric,
        cadence: SearchGoalCadence,
        targetValue: Int,
        isArchived: Bool = false,
        cycle: JobSearchCycle? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.metricRawValue = metric.rawValue
        self.cadenceRawValue = cadence.rawValue
        self.targetValue = targetValue
        self.isArchived = isArchived
        self.cycle = cycle
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var title: String {
        "\(cadence.displayName) \(metric.displayName)"
    }

    public func archive() {
        isArchived = true
        updateTimestamp()
    }

    public func unarchive() {
        isArchived = false
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
