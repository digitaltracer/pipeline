import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ApplicationStatus: Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case saved
    case applied
    case interviewing
    case offered
    case rejected
    case archived
    case custom(String)

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public init(rawValue: String) {
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

    public var rawValue: String {
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

    public var icon: String {
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

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .saved: return Color(red: 0.601, green: 0.634, blue: 0.699)        // slate HSL(220, 14%, 65%)
        case .applied: return Color(red: 0.236, green: 0.515, blue: 0.964)      // blue HSL(217, 91%, 60%)
        case .interviewing: return Color(red: 0.96, green: 0.622, blue: 0.04)   // amber HSL(38, 92%, 50%)
        case .offered: return Color(red: 0.131, green: 0.77, blue: 0.365)       // emerald HSL(142, 71%, 45%)
        case .rejected: return Color(red: 0.936, green: 0.264, blue: 0.264)     // red HSL(0, 84%, 60%)
        case .archived: return .secondary
        case .custom: return .purple
        }
    }
    #endif

    public var sortOrder: Int {
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

    public static var allCases: [ApplicationStatus] {
        [.saved, .applied, .interviewing, .offered, .rejected, .archived]
    }

    // MARK: - Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ApplicationStatus(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
