import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ApplicationActivityKind: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case interview
    case email
    case call
    case text
    case note

    public var id: String { rawValue }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "interview":
            self = .interview
        case "email":
            self = .email
        case "call":
            self = .call
        case "text":
            self = .text
        default:
            self = .note
        }
    }

    public var rawValue: String {
        switch self {
        case .interview:
            return "Interview"
        case .email:
            return "Email"
        case .call:
            return "Call"
        case .text:
            return "Text"
        case .note:
            return "Note"
        }
    }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .interview:
            return "bubble.left.and.bubble.right"
        case .email:
            return "envelope"
        case .call:
            return "phone"
        case .text:
            return "message"
        case .note:
            return "note.text"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .interview:
            return .orange
        case .email:
            return .blue
        case .call:
            return .green
        case .text:
            return .teal
        case .note:
            return .secondary
        }
    }
    #endif

    public var requiresInterviewFields: Bool { self == .interview }
    public var requiresEmailFields: Bool { self == .email }

    public static var allCases: [ApplicationActivityKind] {
        [.interview, .email, .call, .text, .note]
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ApplicationActivityKind(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
