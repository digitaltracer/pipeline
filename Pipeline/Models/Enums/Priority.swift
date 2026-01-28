import Foundation
import SwiftUI

enum Priority: String, Codable, CaseIterable, Identifiable {
    case high = "High"
    case medium = "Medium"
    case low = "Low"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .high: return "flag.fill"
        case .medium: return "flag.fill"
        case .low: return "flag"
        }
    }

    var color: Color {
        switch self {
        case .high: return .red
        case .medium: return .orange
        case .low: return .gray
        }
    }

    var sortOrder: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}
