import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum Priority: String, Codable, CaseIterable, Identifiable, Sendable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .high: return "flag.fill"
        case .medium: return "flag.fill"
        case .low: return "flag"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .high: return Color(red: 0.936, green: 0.264, blue: 0.264)     // red HSL(0, 84%, 60%)
        case .medium: return Color(red: 0.96, green: 0.622, blue: 0.04)     // amber HSL(38, 92%, 50%)
        case .low: return Color(red: 0.131, green: 0.77, blue: 0.365)       // green HSL(142, 71%, 45%)
        }
    }
    #endif

    public var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
