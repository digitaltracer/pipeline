import Foundation
import SwiftData
import PipelineKit

enum AIUsageLedgerService {
    struct CostBreakdown {
        let inputCostUSD: Double?
        let outputCostUSD: Double?
        let totalCostUSD: Double?

        static let unavailable = CostBreakdown(
            inputCostUSD: nil,
            outputCostUSD: nil,
            totalCostUSD: nil
        )
    }

    static func seedDefaultRatesIfNeeded(in modelContext: ModelContext) throws {
        var descriptor = FetchDescriptor<AIModelRate>()
        descriptor.fetchLimit = 1
        let existing = try modelContext.fetch(descriptor)
        guard existing.isEmpty else { return }

        let now = Date()
        for definition in AIPricingDefaults.defaultRates {
            let rate = AIModelRate(
                providerID: definition.providerID,
                model: definition.model,
                inputUSDPerMillion: definition.inputUSDPerMillion,
                outputUSDPerMillion: definition.outputUSDPerMillion,
                updatedAt: now,
                source: .seeded
            )
            modelContext.insert(rate)
        }

        try modelContext.save()
    }

    static func resetRatesToDefaults(in modelContext: ModelContext) throws {
        let existing = try modelContext.fetch(FetchDescriptor<AIModelRate>())
        for rate in existing {
            modelContext.delete(rate)
        }

        let now = Date()
        for definition in AIPricingDefaults.defaultRates {
            let rate = AIModelRate(
                providerID: definition.providerID,
                model: definition.model,
                inputUSDPerMillion: definition.inputUSDPerMillion,
                outputUSDPerMillion: definition.outputUSDPerMillion,
                updatedAt: now,
                source: .seeded
            )
            modelContext.insert(rate)
        }

        try modelContext.save()
    }

    static func upsertRate(
        providerID: String,
        model: String,
        inputUSDPerMillion: Double,
        outputUSDPerMillion: Double,
        source: AIModelRateSource = .user,
        in modelContext: ModelContext
    ) throws {
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProvider.isEmpty, !normalizedModel.isEmpty else { return }

        if let existing = try findRate(providerID: normalizedProvider, model: normalizedModel, in: modelContext) {
            existing.inputUSDPerMillion = max(0, inputUSDPerMillion)
            existing.outputUSDPerMillion = max(0, outputUSDPerMillion)
            existing.source = source
            existing.updatedAt = Date()
        } else {
            let rate = AIModelRate(
                providerID: normalizedProvider,
                model: normalizedModel,
                inputUSDPerMillion: max(0, inputUSDPerMillion),
                outputUSDPerMillion: max(0, outputUSDPerMillion),
                updatedAt: Date(),
                source: source
            )
            modelContext.insert(rate)
        }

        try modelContext.save()
    }

    @discardableResult
    static func record(
        feature: AIUsageFeature,
        provider: AIProvider,
        model: String,
        usage: AIUsageMetrics?,
        status: AIUsageRequestStatus,
        applicationID: UUID? = nil,
        companyID: UUID? = nil,
        startedAt: Date,
        finishedAt: Date = Date(),
        errorMessage: String? = nil,
        in modelContext: ModelContext
    ) throws -> AIUsageRecord {
        try seedDefaultRatesIfNeeded(in: modelContext)

        let promptTokens = usage?.promptTokens
        let completionTokens = usage?.completionTokens
        let totalTokens = usage?.totalTokens ?? {
            guard let promptTokens, let completionTokens else { return nil }
            return promptTokens + completionTokens
        }()

        let costs = try calculateCosts(
            providerID: provider.providerID,
            model: model,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            in: modelContext
        )

        let record = AIUsageRecord(
            feature: feature,
            providerID: provider.providerID,
            model: model,
            requestStatus: status,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            totalTokens: totalTokens,
            inputCostUSD: costs.inputCostUSD,
            outputCostUSD: costs.outputCostUSD,
            totalCostUSD: costs.totalCostUSD,
            applicationID: applicationID,
            companyID: companyID,
            startedAt: startedAt,
            finishedAt: finishedAt,
            errorMessage: errorMessage
        )

        modelContext.insert(record)
        try modelContext.save()
        return record
    }

    private static func calculateCosts(
        providerID: String,
        model: String,
        promptTokens: Int?,
        completionTokens: Int?,
        in modelContext: ModelContext
    ) throws -> CostBreakdown {
        guard let promptTokens, let completionTokens else {
            return .unavailable
        }

        guard let rate = try findRate(providerID: providerID, model: model, in: modelContext) else {
            return .unavailable
        }

        let inputCost = (Double(promptTokens) / 1_000_000) * rate.inputUSDPerMillion
        let outputCost = (Double(completionTokens) / 1_000_000) * rate.outputUSDPerMillion
        let total = inputCost + outputCost

        return CostBreakdown(
            inputCostUSD: roundToMicros(inputCost),
            outputCostUSD: roundToMicros(outputCost),
            totalCostUSD: roundToMicros(total)
        )
    }

    private static func findRate(
        providerID: String,
        model: String,
        in modelContext: ModelContext
    ) throws -> AIModelRate? {
        let normalizedProvider = providerID.lowercased()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)

        var descriptor = FetchDescriptor<AIModelRate>(
            predicate: #Predicate { $0.providerID == normalizedProvider }
        )
        descriptor.sortBy = [SortDescriptor(\AIModelRate.updatedAt, order: .reverse)]
        let rates = try modelContext.fetch(descriptor)

        return rates.first(where: {
            $0.model.caseInsensitiveCompare(normalizedModel) == .orderedSame
        })
    }

    private static func roundToMicros(_ value: Double) -> Double {
        (value * 1_000_000).rounded() / 1_000_000
    }
}
