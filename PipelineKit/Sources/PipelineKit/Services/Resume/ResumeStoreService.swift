import Foundation
import SwiftData

public enum ResumeStoreService {
    public static func currentMasterRevision(in context: ModelContext) throws -> ResumeMasterRevision? {
        var descriptor = FetchDescriptor<ResumeMasterRevision>(
            predicate: #Predicate { $0.isCurrent == true }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public static func masterRevisions(in context: ModelContext) throws -> [ResumeMasterRevision] {
        let descriptor = FetchDescriptor<ResumeMasterRevision>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    @discardableResult
    public static func saveMasterRevision(
        rawJSON: String,
        unknownFieldPaths: [String],
        in context: ModelContext
    ) throws -> ResumeMasterRevision {
        let revisions = try masterRevisions(in: context)
        revisions.forEach { $0.markCurrent(false) }

        let revision = ResumeMasterRevision(
            rawJSON: rawJSON,
            unknownFieldPaths: unknownFieldPaths,
            isCurrent: true
        )
        context.insert(revision)
        try context.save()
        return revision
    }

    public static func restoreMasterRevision(_ revision: ResumeMasterRevision, in context: ModelContext) throws {
        let revisions = try masterRevisions(in: context)
        revisions.forEach { $0.markCurrent($0.id == revision.id) }
        try context.save()
    }

    public static func deleteMasterRevision(_ revision: ResumeMasterRevision, in context: ModelContext) throws {
        let wasCurrent = revision.isCurrent
        context.delete(revision)

        if wasCurrent {
            let remaining = try masterRevisions(in: context)
            if let next = remaining.first {
                next.markCurrent(true)
            }
        }

        try context.save()
    }

    public static func jobSnapshots(for application: JobApplication) -> [ResumeJobSnapshot] {
        application.sortedResumeSnapshots
    }

    @discardableResult
    public static func createJobSnapshot(
        for application: JobApplication,
        rawJSON: String,
        acceptedPatchIDs: [UUID],
        rejectedPatchIDs: [UUID],
        sectionGaps: [String],
        sourceMasterRevisionID: UUID?,
        in context: ModelContext
    ) throws -> ResumeJobSnapshot {
        let snapshot = ResumeJobSnapshot(
            rawJSON: rawJSON,
            acceptedPatchIDs: acceptedPatchIDs,
            rejectedPatchIDs: rejectedPatchIDs,
            sectionGaps: sectionGaps,
            sourceMasterRevisionID: sourceMasterRevisionID
        )
        snapshot.application = application

        if application.resumeSnapshots == nil {
            application.resumeSnapshots = []
        }
        application.resumeSnapshots?.append(snapshot)
        application.updateTimestamp()

        context.insert(snapshot)
        try context.save()
        return snapshot
    }

    public static func deleteJobSnapshot(_ snapshot: ResumeJobSnapshot, in context: ModelContext) throws {
        context.delete(snapshot)
        try context.save()
    }
}
