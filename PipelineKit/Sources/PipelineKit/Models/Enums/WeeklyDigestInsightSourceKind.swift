import Foundation

public enum WeeklyDigestInsightSourceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case rule
    case ai

    public var id: String { rawValue }
}
