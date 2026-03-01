import Foundation

public struct ResumePatch: Codable, Sendable, Equatable, Identifiable {
    public enum Operation: String, Codable, Sendable, CaseIterable {
        case add
        case replace
        case remove
    }

    public enum Risk: String, Codable, Sendable, CaseIterable {
        case low
        case medium
        case high
    }

    public let id: UUID
    public let path: String
    public let operation: Operation
    public let beforeValue: JSONValue?
    public let afterValue: JSONValue?
    public let reason: String
    public let evidencePaths: [String]
    public let risk: Risk

    public init(
        id: UUID = UUID(),
        path: String,
        operation: Operation,
        beforeValue: JSONValue? = nil,
        afterValue: JSONValue? = nil,
        reason: String,
        evidencePaths: [String] = [],
        risk: Risk = .low
    ) {
        self.id = id
        self.path = path
        self.operation = operation
        self.beforeValue = beforeValue
        self.afterValue = afterValue
        self.reason = reason
        self.evidencePaths = evidencePaths
        self.risk = risk
    }
}
