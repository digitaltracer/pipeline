import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Source: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case agent
    case hr
    case jobPortal
    case companyWebsite
    case referral
    case custom(String)

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            self = .jobPortal
            return
        }

        switch normalized.lowercased() {
        case "agent": self = .agent
        case "hr": self = .hr
        case "job portal", "jobportal": self = .jobPortal
        case "company website", "companywebsite": self = .companyWebsite
        case "referral": self = .referral
        default: self = .custom(normalized)
        }
    }

    public var rawValue: String {
        switch self {
        case .agent: return "Agent"
        case .hr: return "HR"
        case .jobPortal: return "Job Portal"
        case .companyWebsite: return "Company Website"
        case .referral: return "Referral"
        case .custom(let value): return value
        }
    }

    public var icon: String {
        switch self {
        case .agent: return "person.badge.shield.checkmark"
        case .hr: return "person.crop.rectangle"
        case .jobPortal: return "globe"
        case .companyWebsite: return "building.2"
        case .referral: return "person.2"
        case .custom: return "tag"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .agent: return .purple
        case .hr: return .blue
        case .jobPortal: return .cyan
        case .companyWebsite: return .orange
        case .referral: return .green
        case .custom: return .secondary
        }
    }
    #endif

    public static var allCases: [Source] {
        [.agent, .hr, .jobPortal, .companyWebsite, .referral]
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Source(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
