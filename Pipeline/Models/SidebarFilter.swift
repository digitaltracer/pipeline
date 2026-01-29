import Foundation
import SwiftUI

enum SidebarFilter: String, CaseIterable, Identifiable {
    case all = "All Applications"
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
        case .all: return "square.grid.2x2"
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
        case .all: return .primary
        case .saved: return .gray
        case .applied: return .blue
        case .interviewing: return .orange
        case .offered: return .green
        case .rejected: return .red
        case .archived: return .secondary
        }
    }

    var status: ApplicationStatus? {
        switch self {
        case .all: return nil
        case .saved: return .saved
        case .applied: return .applied
        case .interviewing: return .interviewing
        case .offered: return .offered
        case .rejected: return .rejected
        case .archived: return .archived
        }
    }

    /// Predicate for filtering applications
    func predicate() -> Predicate<JobApplication>? {
        guard let status = status else { return nil }
        let statusRaw = status.rawValue
        return #Predicate<JobApplication> { application in
            application.statusRawValue == statusRaw
        }
    }
}
