import Foundation

public enum ATSFindingSeverity: String, Codable, CaseIterable, Sendable, Identifiable {
    case success
    case warning
    case critical

    public var id: String { rawValue }
}
