import Foundation

public enum FollowUpCadenceKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case applicationApplied
    case postInterview

    public var id: String { rawValue }
}
