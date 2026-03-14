import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

public enum ReferralAttemptStatus: String, CaseIterable, Codable, Identifiable, Sendable {
    case asked = "Asked"
    case pending = "Pending"
    case received = "Received"
    case declined = "Declined"

    public var id: String { rawValue }

    public var displayName: String { rawValue }

    public var icon: String {
        switch self {
        case .asked:
            return "paperplane"
        case .pending:
            return "clock"
        case .received:
            return "checkmark.circle.fill"
        case .declined:
            return "xmark.circle.fill"
        }
    }

    #if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .asked:
            return .blue
        case .pending:
            return .orange
        case .received:
            return .green
        case .declined:
            return .red
        }
    }
    #endif
}
