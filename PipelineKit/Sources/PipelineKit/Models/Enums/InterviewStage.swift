import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum InterviewStage: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case phoneScreen
    case technicalRound1
    case technicalRound2
    case designChallenge
    case systemDesign
    case hrRound
    case finalRound
    case offerExtended
    case custom(String)

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            self = .phoneScreen
            return
        }

        switch normalized.lowercased() {
        case "phone screen", "phonescreen": self = .phoneScreen
        case "technical round 1", "technical 1", "tech 1": self = .technicalRound1
        case "technical round 2", "technical 2", "tech 2": self = .technicalRound2
        case "design challenge", "design": self = .designChallenge
        case "system design", "system": self = .systemDesign
        case "hr round", "hr": self = .hrRound
        case "final round", "final": self = .finalRound
        case "offer extended", "offer": self = .offerExtended
        default: self = .custom(normalized)
        }
    }

    public var rawValue: String {
        switch self {
        case .phoneScreen: return "Phone Screen"
        case .technicalRound1: return "Technical Round 1"
        case .technicalRound2: return "Technical Round 2"
        case .designChallenge: return "Design Challenge"
        case .systemDesign: return "System Design"
        case .hrRound: return "HR Round"
        case .finalRound: return "Final Round"
        case .offerExtended: return "Offer Extended"
        case .custom(let value): return value
        }
    }

    public var shortName: String {
        switch self {
        case .phoneScreen: return "Phone"
        case .technicalRound1: return "Tech 1"
        case .technicalRound2: return "Tech 2"
        case .designChallenge: return "Design"
        case .systemDesign: return "System"
        case .hrRound: return "HR"
        case .finalRound: return "Final"
        case .offerExtended: return "Offer"
        case .custom(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = trimmed.split(separator: " ").prefix(2)
            let candidate = words.joined(separator: " ")
            if candidate.isEmpty { return "Custom" }
            if candidate.count <= 9 { return candidate }
            return String(candidate.prefix(9))
        }
    }

    public var icon: String {
        switch self {
        case .phoneScreen: return "phone.fill"
        case .technicalRound1, .technicalRound2: return "laptopcomputer"
        case .designChallenge: return "paintbrush.fill"
        case .systemDesign: return "square.3.layers.3d"
        case .hrRound: return "person.fill"
        case .finalRound: return "star.fill"
        case .offerExtended: return "checkmark.seal.fill"
        case .custom: return "tag.fill"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .phoneScreen: return .blue
        case .technicalRound1: return .orange
        case .technicalRound2: return .orange
        case .designChallenge: return .purple
        case .systemDesign: return .cyan
        case .hrRound: return .pink
        case .finalRound: return .yellow
        case .offerExtended: return .green
        case .custom: return .secondary
        }
    }
    #endif

    public var sortOrder: Int {
        switch self {
        case .phoneScreen: return 0
        case .technicalRound1: return 1
        case .technicalRound2: return 2
        case .designChallenge: return 3
        case .systemDesign: return 4
        case .hrRound: return 5
        case .finalRound: return 6
        case .offerExtended: return 7
        case .custom: return 999
        }
    }

    public static var allCases: [InterviewStage] {
        [
            .phoneScreen,
            .technicalRound1,
            .technicalRound2,
            .designChallenge,
            .systemDesign,
            .hrRound,
            .finalRound,
            .offerExtended
        ]
    }

    public static var orderedCases: [InterviewStage] {
        allCases.sorted { $0.sortOrder < $1.sortOrder }
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = InterviewStage(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
