import Foundation
import SwiftData

@Model
public final class ResumeMasterRevision {
    public var id: UUID = UUID()
    public var rawJSON: String = ""
    public var unknownFieldPaths: [String] = []
    public var isCurrent: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        rawJSON: String,
        unknownFieldPaths: [String] = [],
        isCurrent: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.rawJSON = rawJSON
        self.unknownFieldPaths = unknownFieldPaths
        self.isCurrent = isCurrent
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func markCurrent(_ current: Bool) {
        isCurrent = current
        updatedAt = Date()
    }
}
