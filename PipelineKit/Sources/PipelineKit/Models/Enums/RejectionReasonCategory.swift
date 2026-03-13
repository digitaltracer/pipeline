import Foundation

public enum RejectionReasonCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case noResponse
    case experienceMismatch
    case skillsMismatch
    case domainMismatch
    case compensation
    case locationOrVisa
    case headcount
    case cultureFit
    case other
    case unknown

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .noResponse:
            return "No Response"
        case .experienceMismatch:
            return "Experience Mismatch"
        case .skillsMismatch:
            return "Skills Mismatch"
        case .domainMismatch:
            return "Domain Mismatch"
        case .compensation:
            return "Compensation"
        case .locationOrVisa:
            return "Location or Visa"
        case .headcount:
            return "Headcount"
        case .cultureFit:
            return "Culture Fit"
        case .other:
            return "Other"
        case .unknown:
            return "Unknown"
        }
    }
}
