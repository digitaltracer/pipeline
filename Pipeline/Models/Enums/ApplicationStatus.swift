import Foundation
import SwiftUI

enum ApplicationStatus: Codable, CaseIterable, Identifiable, Hashable {
    case saved
    case applied
    case interviewing
    case offered
    case rejected
    case archived
    case custom(String)

    var id: String { rawValue }

    var displayName: String { rawValue }

    init(rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            self = .saved
            return
        }

        switch normalized.lowercased() {
        case "saved": self = .saved
        case "applied": self = .applied
        case "interviewing": self = .interviewing
        case "offered": self = .offered
        case "rejected": self = .rejected
        case "archived": self = .archived
        default: self = .custom(normalized)
        }
    }

    var rawValue: String {
        switch self {
        case .saved: return "Saved"
        case .applied: return "Applied"
        case .interviewing: return "Interviewing"
        case .offered: return "Offered"
        case .rejected: return "Rejected"
        case .archived: return "Archived"
        case .custom(let value): return value
        }
    }

    var icon: String {
        switch self {
        case .saved: return "bookmark.fill"
        case .applied: return "paperplane.fill"
        case .interviewing: return "person.2.fill"
        case .offered: return "gift.fill"
        case .rejected: return "xmark.circle.fill"
        case .archived: return "archivebox.fill"
        case .custom: return "tag.fill"
        }
    }

    var color: Color {
        switch self {
        case .saved: return .gray
        case .applied: return .blue
        case .interviewing: return .orange
        case .offered: return .green
        case .rejected: return .red
        case .archived: return .secondary
        case .custom: return .purple
        }
    }

    var sortOrder: Int {
        switch self {
        case .saved: return 0
        case .applied: return 1
        case .interviewing: return 2
        case .offered: return 3
        case .rejected: return 4
        case .archived: return 5
        case .custom: return 999
        }
    }

    static var allCases: [ApplicationStatus] {
        [.saved, .applied, .interviewing, .offered, .rejected, .archived]
    }

    // MARK: - Codable

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ApplicationStatus(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
