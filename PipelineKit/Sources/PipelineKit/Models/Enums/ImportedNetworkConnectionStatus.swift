import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ImportedNetworkConnectionStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case available = "Available"
    case promoted = "Promoted"
    case ignored = "Ignored"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .available:
            return "person.2"
        case .promoted:
            return "person.crop.circle.badge.checkmark"
        case .ignored:
            return "eye.slash"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .available:
            return .blue
        case .promoted:
            return .green
        case .ignored:
            return .secondary
        }
    }
    #endif
}
