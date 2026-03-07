import Foundation

public enum ApplicationAttachmentKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case file = "file"
    case link = "link"
    case note = "note"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .file:
            return "File"
        case .link:
            return "Link"
        case .note:
            return "Note"
        }
    }

    public var icon: String {
        switch self {
        case .file:
            return "doc"
        case .link:
            return "link"
        case .note:
            return "note.text"
        }
    }
}
