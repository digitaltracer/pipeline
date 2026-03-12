import Foundation
import SwiftData

public struct ResumeSourceSelection: Sendable {
    public enum Kind: String, Sendable {
        case tailoredSnapshot = "tailored_snapshot"
        case masterResume = "master_resume"
    }

    public let kind: Kind
    public let rawJSON: String
    public let snapshotID: UUID?
    public let masterRevisionID: UUID?
    public let createdAt: Date

    public init(
        kind: Kind,
        rawJSON: String,
        snapshotID: UUID?,
        masterRevisionID: UUID?,
        createdAt: Date
    ) {
        self.kind = kind
        self.rawJSON = rawJSON
        self.snapshotID = snapshotID
        self.masterRevisionID = masterRevisionID
        self.createdAt = createdAt
    }

    public var label: String {
        switch kind {
        case .tailoredSnapshot:
            return "Latest Tailored Resume"
        case .masterResume:
            return "Master Resume"
        }
    }
}

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

    public static func preferredResumeSource(
        for application: JobApplication,
        in context: ModelContext
    ) throws -> ResumeSourceSelection? {
        if let snapshot = application.sortedResumeSnapshots.first {
            return ResumeSourceSelection(
                kind: .tailoredSnapshot,
                rawJSON: snapshot.rawJSON,
                snapshotID: snapshot.id,
                masterRevisionID: snapshot.sourceMasterRevisionID,
                createdAt: snapshot.createdAt
            )
        }

        if let masterRevision = try currentMasterRevision(in: context) {
            return ResumeSourceSelection(
                kind: .masterResume,
                rawJSON: masterRevision.rawJSON,
                snapshotID: nil,
                masterRevisionID: masterRevision.id,
                createdAt: masterRevision.createdAt
            )
        }

        return nil
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
        try ApplicationChecklistService().sync(for: application, trigger: .resumeSnapshotSaved, in: context)
        return snapshot
    }

    public static func deleteJobSnapshot(_ snapshot: ResumeJobSnapshot, in context: ModelContext) throws {
        context.delete(snapshot)
        try context.save()
    }
}
