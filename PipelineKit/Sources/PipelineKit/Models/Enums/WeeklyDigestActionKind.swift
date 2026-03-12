import Foundation

public enum WeeklyDigestActionKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case interview
    case followUp
    case tailoring
    case task
    case summary

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .interview:
            return "Interview"
        case .followUp:
            return "Follow-up"
        case .tailoring:
            return "Tailoring"
        case .task:
            return "Task"
        case .summary:
            return "Summary"
        }
    }
}
