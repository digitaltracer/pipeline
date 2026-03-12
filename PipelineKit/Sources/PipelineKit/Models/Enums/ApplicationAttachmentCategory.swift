import Foundation

public enum ApplicationAttachmentCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case resume = "resume"
    case coverLetter = "cover_letter"
    case offer = "offer"
    case contract = "contract"
    case note = "note"
    case link = "link"
    case other = "other"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .resume:
            return "Resume"
        case .coverLetter:
            return "Cover Letter"
        case .offer:
            return "Offer"
        case .contract:
            return "Contract"
        case .note:
            return "Note"
        case .link:
            return "Link"
        case .other:
            return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .resume:
            return "doc.text"
        case .coverLetter:
            return "envelope"
        case .offer:
            return "rosette"
        case .contract:
            return "signature"
        case .note:
            return "note.text"
        case .link:
            return "link"
        case .other:
            return "paperclip"
        }
    }
}
