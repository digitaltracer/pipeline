import Foundation

public enum SearchGoalCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case weekly
    case monthly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .weekly:
            return "Weekly"
        case .monthly:
            return "Monthly"
        }
    }
}
