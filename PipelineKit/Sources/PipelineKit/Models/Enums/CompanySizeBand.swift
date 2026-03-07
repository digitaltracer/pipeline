import Foundation

public enum CompanySizeBand: String, Codable, CaseIterable, Sendable, Identifiable {
    case startup = "startup"
    case small = "small"
    case midsize = "midsize"
    case enterprise = "enterprise"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .startup:
            return "Startup"
        case .small:
            return "Small"
        case .midsize:
            return "Midsize"
        case .enterprise:
            return "Enterprise"
        }
    }
}
