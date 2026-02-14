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
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
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
