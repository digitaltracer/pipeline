import Foundation
import SwiftData

public enum JobSearchCycleMigrationService {
    @discardableResult
    public static func backfillImportedCycleIfNeeded(in context: ModelContext) throws -> JobSearchCycle? {
        let cycleCount = try context.fetchCount(FetchDescriptor<JobSearchCycle>())
        let applications = try context.fetch(FetchDescriptor<JobApplication>())

        guard !applications.isEmpty else { return nil }

        if cycleCount == 0 {
            let importedCycle = JobSearchCycle(
                name: "Imported Search",
                startDate: applications.map(\.createdAt).min() ?? Date(),
                isActive: applications.contains(where: { $0.status != .archived && $0.status != .rejected })
            )
            context.insert(importedCycle)

            for application in applications {
                application.assignCycle(importedCycle)
            }

            try context.save()
            return importedCycle
        }

        let uncategorized = applications.filter { $0.cycle == nil }
        guard !uncategorized.isEmpty else { return nil }

        let descriptor = FetchDescriptor<JobSearchCycle>(
            predicate: #Predicate<JobSearchCycle> { $0.name == "Imported Search" }
        )
        let existingImportedCycle = try context.fetch(descriptor).first
        let importedCycle = existingImportedCycle ?? JobSearchCycle(
            name: "Imported Search",
            startDate: uncategorized.map(\.createdAt).min() ?? Date(),
            isActive: uncategorized.contains(where: { $0.status != .archived && $0.status != .rejected })
        )

        if existingImportedCycle == nil {
            context.insert(importedCycle)
        }

        for application in uncategorized {
            application.assignCycle(importedCycle)
        }

        try context.save()
        return importedCycle
    }

    public static func activeCycle(in context: ModelContext) throws -> JobSearchCycle? {
        let cycles = try context.fetch(FetchDescriptor<JobSearchCycle>())
        return cycles
            .sorted { lhs, rhs in
                if lhs.isActive != rhs.isActive {
                    return lhs.isActive && !rhs.isActive
                }
                if lhs.startDate != rhs.startDate {
                    return lhs.startDate > rhs.startDate
                }
                return lhs.updatedAt > rhs.updatedAt
            }
            .first(where: \.isActive)
    }

    public static func cycle(withID id: UUID, in context: ModelContext) throws -> JobSearchCycle? {
        let cycles = try context.fetch(FetchDescriptor<JobSearchCycle>())
        return cycles.first(where: { $0.id == id })
    }

    @discardableResult
    public static func ensureActiveCycle(in context: ModelContext, referenceDate: Date = Date()) throws -> JobSearchCycle {
        if let activeCycle = try activeCycle(in: context) {
            return activeCycle
        }

        let cycles = try context.fetch(FetchDescriptor<JobSearchCycle>())
        if let latest = cycles.sorted(by: { $0.startDate > $1.startDate }).first {
            latest.activate()
            try context.save()
            return latest
        }

        let newCycle = JobSearchCycle(
            name: "Current Search",
            startDate: referenceDate,
            isActive: true
        )
        context.insert(newCycle)
        try context.save()
        return newCycle
    }

    public static func activate(_ cycle: JobSearchCycle, in context: ModelContext) throws {
        let cycles = try context.fetch(FetchDescriptor<JobSearchCycle>())
        for existing in cycles where existing.id != cycle.id && existing.isActive {
            existing.isActive = false
            existing.updateTimestamp()
        }
        cycle.activate()
        try context.save()
    }
}
