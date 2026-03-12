import Foundation

public enum JobMatchAssessmentStatus: String, Codable, CaseIterable, Sendable, Identifiable {
    case ready
    case blocked
    case failed

    public var id: String { rawValue }
}
