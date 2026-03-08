import Foundation

public enum ApplicationTaskOrigin: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case manual
    case smartChecklist

    public var id: String { rawValue }
}
