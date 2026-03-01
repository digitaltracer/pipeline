import Foundation
import SwiftData

@Model
public final class ResumeJobSnapshot {
    public var id: UUID = UUID()
    public var rawJSON: String = ""
    public var acceptedPatchIDs: [UUID] = []
    public var rejectedPatchIDs: [UUID] = []
    public var sectionGaps: [String] = []
    public var sourceMasterRevisionID: UUID?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public init(
        id: UUID = UUID(),
        rawJSON: String,
        acceptedPatchIDs: [UUID] = [],
        rejectedPatchIDs: [UUID] = [],
        sectionGaps: [String] = [],
        sourceMasterRevisionID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.rawJSON = rawJSON
        self.acceptedPatchIDs = acceptedPatchIDs
        self.rejectedPatchIDs = rejectedPatchIDs
        self.sectionGaps = sectionGaps
        self.sourceMasterRevisionID = sourceMasterRevisionID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
