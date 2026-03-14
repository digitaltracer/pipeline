import Foundation
import SwiftData

@MainActor
public final class OfferComparisonWorksheetService {
    public init() {}

    public func loadOrCreateWorksheet(
        in context: ModelContext,
        offeredApplications: [JobApplication]
    ) throws -> OfferComparisonWorksheet {
        let descriptor = FetchDescriptor<OfferComparisonWorksheet>()
        let worksheet = try context.fetch(descriptor).first ?? makeWorksheet(context: context, offeredApplications: offeredApplications)

        ensureBuiltInFactors(on: worksheet, context: context)
        sync(worksheet: worksheet, offeredApplications: offeredApplications)
        ensureValueCoverage(on: worksheet, applicationIDs: worksheet.knownApplicationIDs, context: context)

        if context.hasChanges {
            try context.save()
        }

        return worksheet
    }

    public func sync(
        worksheet: OfferComparisonWorksheet,
        offeredApplications: [JobApplication]
    ) {
        let offeredIDs = offeredApplications.map(\.id)
        let newIDs = offeredIDs.filter { !worksheet.knownApplicationIDs.contains($0) }
        let selectedIDs = worksheet.selectedApplicationIDs.filter { offeredIDs.contains($0) } + newIDs

        worksheet.setKnownApplicationIDs((worksheet.knownApplicationIDs + offeredIDs).uniquedPreservingOrder())
        worksheet.setSelectedApplicationIDs(selectedIDs.uniquedPreservingOrder())
    }

    @discardableResult
    public func addCustomFactor(
        titled title: String,
        to worksheet: OfferComparisonWorksheet,
        context: ModelContext
    ) throws -> OfferComparisonFactor {
        let factor = OfferComparisonFactor(
            kind: .custom,
            title: title,
            weight: 1,
            sortOrder: nextSortOrder(in: worksheet),
            worksheet: worksheet
        )
        worksheet.addFactor(factor)
        context.insert(factor)
        try context.save()
        return factor
    }

    public func deleteCustomFactor(
        _ factor: OfferComparisonFactor,
        context: ModelContext
    ) throws {
        context.delete(factor)
        try context.save()
    }

    public func setSelection(
        applicationID: UUID,
        isSelected: Bool,
        on worksheet: OfferComparisonWorksheet,
        context: ModelContext
    ) throws {
        var ids = worksheet.selectedApplicationIDs
        if isSelected {
            if !ids.contains(applicationID) {
                ids.append(applicationID)
            }
        } else {
            ids.removeAll(where: { $0 == applicationID })
        }
        worksheet.setSelectedApplicationIDs(ids)
        try context.save()
    }

    public func upsertValue(
        for factor: OfferComparisonFactor,
        applicationID: UUID,
        displayText: String?,
        score: Int?,
        context: ModelContext
    ) throws {
        let value = factor.upsertValue(applicationID: applicationID, displayText: displayText, score: score)
        if value.modelContext == nil {
            context.insert(value)
        }
        try context.save()
    }

    private func makeWorksheet(
        context: ModelContext,
        offeredApplications: [JobApplication]
    ) -> OfferComparisonWorksheet {
        let offeredIDs = offeredApplications.map(\.id)
        let worksheet = OfferComparisonWorksheet(
            selectedApplicationIDs: offeredIDs,
            knownApplicationIDs: offeredIDs
        )
        context.insert(worksheet)
        return worksheet
    }

    private func ensureBuiltInFactors(
        on worksheet: OfferComparisonWorksheet,
        context: ModelContext
    ) {
        let existingKinds = Set(worksheet.sortedFactors.map(\.kind))

        for (index, kind) in OfferComparisonFactorKind.builtInCases.enumerated() where !existingKinds.contains(kind) {
            let factor = OfferComparisonFactor(
                kind: kind,
                title: kind.title,
                weight: 1,
                sortOrder: index,
                worksheet: worksheet
            )
            worksheet.addFactor(factor)
            context.insert(factor)
        }
    }

    private func ensureValueCoverage(
        on worksheet: OfferComparisonWorksheet,
        applicationIDs: [UUID],
        context: ModelContext
    ) {
        for factor in worksheet.sortedFactors {
            guard factor.kind.isCompensation || factor.kind == .custom else { continue }
            for applicationID in applicationIDs where factor.value(for: applicationID) == nil {
                let value = factor.upsertValue(applicationID: applicationID, displayText: nil, score: nil)
                if value.modelContext == nil {
                    context.insert(value)
                }
            }
        }
    }

    private func nextSortOrder(in worksheet: OfferComparisonWorksheet) -> Int {
        (worksheet.sortedFactors.last?.sortOrder ?? -1) + 1
    }
}
