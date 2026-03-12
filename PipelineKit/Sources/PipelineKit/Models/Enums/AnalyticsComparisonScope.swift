import Foundation

public enum AnalyticsComparisonScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case thisWeek
    case thisMonth
    case currentCycle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .thisWeek:
            return "This Week"
        case .thisMonth:
            return "This Month"
        case .currentCycle:
            return "Current Cycle"
        }
    }

    public var comparisonTitle: String {
        switch self {
        case .thisWeek:
            return "vs last week"
        case .thisMonth:
            return "vs last month"
        case .currentCycle:
            return "vs previous cycle"
        }
    }
}
