import Foundation

public enum SearchGoalMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case applicationsSubmitted
    case interviewsBooked
    case offersReceived

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .applicationsSubmitted:
            return "Applications"
        case .interviewsBooked:
            return "Interviews"
        case .offersReceived:
            return "Offers"
        }
    }

    public var icon: String {
        switch self {
        case .applicationsSubmitted:
            return "paperplane.fill"
        case .interviewsBooked:
            return "person.2.fill"
        case .offersReceived:
            return "gift.fill"
        }
    }
}
