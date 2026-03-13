import Foundation

public enum RejectionFeedbackSource: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case explicit
    case inferred
    case none

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .explicit:
            return "Explicit"
        case .inferred:
            return "Inferred"
        case .none:
            return "None"
        }
    }
}
