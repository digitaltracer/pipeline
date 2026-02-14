import Foundation
import SwiftData
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum SidebarFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All Applications"
    case saved = "Saved"
    case applied = "Applied"
    case interviewing = "Interviewing"
    case offered = "Offered"
    case rejected = "Rejected"
    case archived = "Archived"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var icon: String {
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

    #if canImport(SwiftUI)
    public var color: Color {
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
    #endif

    public var status: ApplicationStatus? {
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
    public func predicate() -> Predicate<JobApplication>? {
        guard let status = status else { return nil }
        let statusRaw = status.rawValue
        return #Predicate<JobApplication> { application in
            application.statusRawValue == statusRaw
        }
    }
}
