import Foundation

public enum GoogleCalendarImportState: String, CaseIterable, Codable {
    case pendingReview
    case imported
    case ignored
    case upstreamDeleted
    case updatePending

    public var displayName: String {
        switch self {
        case .pendingReview:
            return "Pending Review"
        case .imported:
            return "Imported"
        case .ignored:
            return "Ignored"
        case .upstreamDeleted:
            return "Upstream Deleted"
        case .updatePending:
            return "Update Pending"
        }
    }

    public var icon: String {
        switch self {
        case .pendingReview:
            return "tray.and.arrow.down"
        case .imported:
            return "checkmark.circle.fill"
        case .ignored:
            return "eye.slash"
        case .upstreamDeleted:
            return "trash.slash"
        case .updatePending:
            return "arrow.triangle.2.circlepath"
        }
    }

    public var needsReview: Bool {
        switch self {
        case .pendingReview, .upstreamDeleted, .updatePending:
            return true
        case .imported, .ignored:
            return false
        }
    }
}
