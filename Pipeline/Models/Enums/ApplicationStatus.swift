import Foundation
import SwiftUI

enum ApplicationStatus: String, Codable, CaseIterable, Identifiable {
    case saved = "Saved"
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offered = "Offered"
    case rejected = "Rejected"
    case archived = "Archived"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .saved: return "bookmark.fill"
        case .applied: return "paperplane.fill"
        case .interviewing: return "person.2.fill"
        case .offered: return "gift.fill"
        case .rejected: return "xmark.circle.fill"
        case .archived: return "archivebox.fill"
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
        }
    }
}
