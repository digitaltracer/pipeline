import Foundation

public enum FollowUpStepState: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case pending
    case snoozed
    case completed
    case dismissed

    public var id: String { rawValue }

    public var isActive: Bool {
        switch self {
        case .pending, .snoozed:
            return true
        case .completed, .dismissed:
            return false
        }
    }
}
