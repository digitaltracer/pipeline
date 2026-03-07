import Foundation

public struct CompanyCompensationComparisonRow: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let sourceLabel: String
    public let rangeText: String
    public let secondaryText: String?
    public let capturedAt: Date

    public init(
        id: UUID,
        label: String,
        sourceLabel: String,
        rangeText: String,
        secondaryText: String? = nil,
        capturedAt: Date
    ) {
        self.id = id
        self.label = label
        self.sourceLabel = sourceLabel
        self.rangeText = rangeText
        self.secondaryText = secondaryText
        self.capturedAt = capturedAt
    }
}

public struct CompanyCompensationComparisonResult: Sendable {
    public let baseCurrency: Currency
    public let internalRows: [CompanyCompensationComparisonRow]
    public let externalRows: [CompanyCompensationComparisonRow]
    public let currentApplicationRangeText: String?
    public let missingConversionCount: Int

    public init(
        baseCurrency: Currency,
        internalRows: [CompanyCompensationComparisonRow],
        externalRows: [CompanyCompensationComparisonRow],
        currentApplicationRangeText: String?,
        missingConversionCount: Int
    ) {
        self.baseCurrency = baseCurrency
        self.internalRows = internalRows
        self.externalRows = externalRows
        self.currentApplicationRangeText = currentApplicationRangeText
        self.missingConversionCount = missingConversionCount
    }
}

public final class CompanyCompensationComparisonService: @unchecked Sendable {
    private let exchangeRateService: ExchangeRateProviding

    public init(exchangeRateService: ExchangeRateProviding = ExchangeRateService.shared) {
        self.exchangeRateService = exchangeRateService
    }

    public func makeComparison(
        for application: JobApplication,
        company: CompanyProfile,
        baseCurrency: Currency
    ) async -> CompanyCompensationComparisonResult {
        var missingConversionCount = 0
        var internalRows: [CompanyCompensationComparisonRow] = []
        var externalRows: [CompanyCompensationComparisonRow] = []

        for peer in company.sortedApplications where peer.id != application.id {
            guard let range = await convertedRange(
                min: peer.expectedTotalCompMin ?? peer.postedTotalCompMin ?? peer.offerTotalComp,
                max: peer.expectedTotalCompMax ?? peer.postedTotalCompMax ?? peer.offerTotalComp,
                currency: peer.currency,
                baseCurrency: baseCurrency,
                date: peer.updatedAt
            ) else {
                missingConversionCount += 1
                continue
            }

            internalRows.append(
                CompanyCompensationComparisonRow(
                    id: peer.id,
                    label: "\(peer.role) · \(peer.location)",
                    sourceLabel: "Pipeline",
                    rangeText: baseCurrency.formatRange(min: range.min, max: range.max) ?? "—",
                    secondaryText: peer.status.displayName,
                    capturedAt: peer.updatedAt
                )
            )
        }

        for snapshot in company.sortedSalarySnapshots where snapshot.matches(roleTitle: application.role, location: application.location) {
            guard let range = await convertedRange(
                min: snapshot.minTotalCompensation ?? snapshot.minBaseCompensation,
                max: snapshot.maxTotalCompensation ?? snapshot.maxBaseCompensation,
                currency: snapshot.currency,
                baseCurrency: baseCurrency,
                date: snapshot.capturedAt
            ) else {
                missingConversionCount += 1
                continue
            }

            externalRows.append(
                CompanyCompensationComparisonRow(
                    id: snapshot.id,
                    label: "\(snapshot.roleTitle) · \(snapshot.location)",
                    sourceLabel: snapshot.sourceName,
                    rangeText: baseCurrency.formatRange(min: range.min, max: range.max) ?? "—",
                    secondaryText: snapshot.confidenceNotes ?? snapshot.notes,
                    capturedAt: snapshot.capturedAt
                )
            )
        }

        let currentRangeText = await convertedRangeText(for: application, baseCurrency: baseCurrency)

        return CompanyCompensationComparisonResult(
            baseCurrency: baseCurrency,
            internalRows: internalRows,
            externalRows: externalRows,
            currentApplicationRangeText: currentRangeText,
            missingConversionCount: missingConversionCount
        )
    }

    private func convertedRangeText(
        for application: JobApplication,
        baseCurrency: Currency
    ) async -> String? {
        let min = application.expectedTotalCompMin ?? application.postedTotalCompMin ?? application.offerTotalComp
        let max = application.expectedTotalCompMax ?? application.postedTotalCompMax ?? application.offerTotalComp

        guard let range = await convertedRange(
            min: min,
            max: max,
            currency: application.currency,
            baseCurrency: baseCurrency,
            date: application.updatedAt
        ) else {
            return nil
        }

        return baseCurrency.formatRange(min: range.min, max: range.max)
    }

    private func convertedRange(
        min: Int?,
        max: Int?,
        currency: Currency,
        baseCurrency: Currency,
        date: Date
    ) async -> (min: Int?, max: Int?)? {
        guard min != nil || max != nil else { return nil }

        let convertedMin = await convert(min, currency: currency, baseCurrency: baseCurrency, date: date)
        let convertedMax = await convert(max, currency: currency, baseCurrency: baseCurrency, date: date)

        if min != nil && convertedMin == nil {
            return nil
        }
        if max != nil && convertedMax == nil {
            return nil
        }

        return (convertedMin, convertedMax)
    }

    private func convert(
        _ amount: Int?,
        currency: Currency,
        baseCurrency: Currency,
        date: Date
    ) async -> Int? {
        guard let amount else { return nil }
        if currency == baseCurrency {
            return amount
        }
        let converted = await exchangeRateService.convert(amount: amount, from: currency, to: baseCurrency, on: date)
        return converted.map { Int($0.amount.rounded()) }
    }
}
