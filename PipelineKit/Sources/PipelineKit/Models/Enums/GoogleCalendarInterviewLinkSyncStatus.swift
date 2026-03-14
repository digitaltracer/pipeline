import Foundation

public enum GoogleCalendarInterviewLinkSyncStatus: String, Codable, CaseIterable, Sendable {
    case active
    case deletedUpstream
    case permissionError
    case orphaned

    public var displayName: String {
        switch self {
        case .active:
            return "Active"
        case .deletedUpstream:
            return "Deleted Upstream"
        case .permissionError:
            return "Permission Error"
        case .orphaned:
            return "Orphaned"
        }
    }

    public var icon: String {
        switch self {
        case .active:
            return "checkmark.circle.fill"
        case .deletedUpstream:
            return "trash.slash"
        case .permissionError:
            return "exclamationmark.lock.fill"
        case .orphaned:
            return "link.badge.minus"
        }
    }
}
