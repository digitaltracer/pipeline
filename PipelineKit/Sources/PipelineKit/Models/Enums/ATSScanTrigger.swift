import Foundation

public enum ATSScanTrigger: String, Codable, CaseIterable, Sendable, Identifiable {
    case autoSnapshot = "auto_snapshot"
    case autoViewRefresh = "auto_view_refresh"
    case manualRescan = "manual_rescan"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .autoSnapshot:
            return "Snapshot Save"
        case .autoViewRefresh:
            return "Auto Refresh"
        case .manualRescan:
            return "Manual Re-scan"
        }
    }
}
