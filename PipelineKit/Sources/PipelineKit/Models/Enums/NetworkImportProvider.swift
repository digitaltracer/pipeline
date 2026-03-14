import Foundation

public enum NetworkImportProvider: String, CaseIterable, Codable, Identifiable, Sendable {
    case linkedInCSV = "LinkedIn CSV"

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}
