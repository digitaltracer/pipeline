import Foundation

public enum ApplicationChecklistSuggestionStatus: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case pending
    case accepted
    case dismissed

    public var id: String { rawValue }

    public var sortOrder: Int {
        switch self {
        case .pending:
            return 0
        case .accepted:
            return 1
        case .dismissed:
            return 2
        }
    }
}
