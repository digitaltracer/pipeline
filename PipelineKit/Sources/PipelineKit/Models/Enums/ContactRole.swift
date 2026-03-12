import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ContactRole: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case recruiter
    case hiringManager
    case interviewer
    case referrer
    case other

    public var id: String { rawValue }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "recruiter":
            self = .recruiter
        case "hiring manager", "hiringmanager":
            self = .hiringManager
        case "interviewer":
            self = .interviewer
        case "referrer":
            self = .referrer
        default:
            self = .other
        }
    }

    public var rawValue: String {
        switch self {
        case .recruiter:
            return "Recruiter"
        case .hiringManager:
            return "Hiring Manager"
        case .interviewer:
            return "Interviewer"
        case .referrer:
            return "Referrer"
        case .other:
            return "Other"
        }
    }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .recruiter:
            return "person.badge.plus"
        case .hiringManager:
            return "person.crop.square"
        case .interviewer:
            return "person.2"
        case .referrer:
            return "arrowshape.turn.up.left"
        case .other:
            return "person"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .recruiter:
            return .blue
        case .hiringManager:
            return .indigo
        case .interviewer:
            return .orange
        case .referrer:
            return .green
        case .other:
            return .secondary
        }
    }
    #endif

    public static var allCases: [ContactRole] {
        [.recruiter, .hiringManager, .interviewer, .referrer, .other]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ContactRole(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
