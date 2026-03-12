import Foundation

public enum CoverLetterSectionKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case greeting = "greeting"
    case hook = "hook"
    case bodyParagraph = "body_paragraph"
    case closing = "closing"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .greeting:
            return "Greeting"
        case .hook:
            return "Hook"
        case .bodyParagraph:
            return "Body Paragraph"
        case .closing:
            return "Closing"
        }
    }
}
