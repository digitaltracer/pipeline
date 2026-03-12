import Foundation

public enum CoverLetterTone: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case formal = "formal"
    case conversational = "conversational"
    case enthusiastic = "enthusiastic"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .formal:
            return "Formal"
        case .conversational:
            return "Conversational"
        case .enthusiastic:
            return "Enthusiastic"
        }
    }

    public var promptDescriptor: String {
        switch self {
        case .formal:
            return "professional, polished, and structured"
        case .conversational:
            return "warm, approachable, and human without losing professionalism"
        case .enthusiastic:
            return "energetic, confident, and positive without sounding exaggerated"
        }
    }

    public var subtitle: String {
        switch self {
        case .formal:
            return "Professional and structured"
        case .conversational:
            return "Friendly and approachable"
        case .enthusiastic:
            return "Energetic and confident"
        }
    }
}
