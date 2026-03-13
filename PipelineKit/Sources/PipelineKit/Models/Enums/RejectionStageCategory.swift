import Foundation

public enum RejectionStageCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case preScreen
    case phoneScreen
    case technical
    case final
    case offerStage
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .preScreen:
            return "Pre-screen"
        case .phoneScreen:
            return "Phone Screen"
        case .technical:
            return "Technical"
        case .final:
            return "Final"
        case .offerStage:
            return "Offer Stage"
        case .unknown:
            return "Unknown"
        }
    }
}
