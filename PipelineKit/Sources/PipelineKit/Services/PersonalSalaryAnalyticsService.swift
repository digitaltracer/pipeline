import Foundation

public struct PersonalSalaryAnalyticsResult: Sendable {
    public let baseCurrency: Currency
    public let expectedDataPointCount: Int
    public let expectedClusterMin: Int?
    public let expectedClusterMax: Int?
    public let askOfferOverlapCount: Int
    public let averageOfferDeltaAmount: Int?
    public let averageOfferDeltaPercent: Double?
    public let summaryText: String?
    public let latestCompensationDate: Date?
    public let isStale: Bool

    public init(
        baseCurrency: Currency,
        expectedDataPointCount: Int,
        expectedClusterMin: Int?,
        expectedClusterMax: Int?,
        askOfferOverlapCount: Int,
        averageOfferDeltaAmount: Int?,
        averageOfferDeltaPercent: Double?,
        summaryText: String?,
        latestCompensationDate: Date?,
        isStale: Bool
    ) {
        self.baseCurrency = baseCurrency
        self.expectedDataPointCount = expectedDataPointCount
        self.expectedClusterMin = expectedClusterMin
        self.expectedClusterMax = expectedClusterMax
        self.askOfferOverlapCount = askOfferOverlapCount
        self.averageOfferDeltaAmount = averageOfferDeltaAmount
        self.averageOfferDeltaPercent = averageOfferDeltaPercent
        self.summaryText = summaryText
        self.latestCompensationDate = latestCompensationDate
        self.isStale = isStale
    }
}

public final class PersonalSalaryAnalyticsService: @unchecked Sendable {
    public static let minimumExpectedCount = 10
    public static let minimumAskOfferOverlap = 3
    public static let staleWindowDays = 180

    private let exchangeRateService: ExchangeRateProviding

    public init(exchangeRateService: ExchangeRateProviding = ExchangeRateService.shared) {
        self.exchangeRateService = exchangeRateService
    }

    public func analyze(
        applications: [JobApplication],
        baseCurrency: Currency
    ) async -> PersonalSalaryAnalyticsResult? {
        var expectedValues: [(value: Int, date: Date)] = []
        var offerDeltas: [(amount: Int, percent: Double, date: Date)] = []
        var rateCache: [String: ExchangeRateService.ConversionResult?] = [:]

        for application in applications {
            if let expectedMidpoint = midpoint(min: application.expectedTotalCompMin, max: application.expectedTotalCompMax),
               let convertedExpected = await convertValue(
                expectedMidpoint,
                from: application.currency,
                to: baseCurrency,
                on: application.updatedAt,
                rateCache: &rateCache
               ) {
                expectedValues.append((Int(convertedExpected.amount.rounded()), application.updatedAt))
            }

            if let expectedMidpoint = midpoint(min: application.expectedTotalCompMin, max: application.expectedTotalCompMax),
               let offerTotal = application.offerTotalComp,
               let convertedExpected = await convertValue(
                expectedMidpoint,
                from: application.currency,
                to: baseCurrency,
                on: application.updatedAt,
                rateCache: &rateCache
               ),
               let convertedOffer = await convertValue(
                offerTotal,
                from: application.currency,
                to: baseCurrency,
                on: application.updatedAt,
                rateCache: &rateCache
               ) {
                let expectedAmount = Int(convertedExpected.amount.rounded())
                let offerAmount = Int(convertedOffer.amount.rounded())
                let deltaAmount = offerAmount - expectedAmount
                let deltaPercent = expectedAmount == 0 ? 0 : (Double(deltaAmount) / Double(expectedAmount)) * 100
                offerDeltas.append((deltaAmount, deltaPercent, application.updatedAt))
            }
        }

        guard expectedValues.count >= Self.minimumExpectedCount || offerDeltas.count >= Self.minimumAskOfferOverlap else {
            return nil
        }

        let expectedSorted = expectedValues.map(\.value).sorted()
        let clusterMin = expectedValues.count >= Self.minimumExpectedCount
            ? percentile(expectedSorted, fraction: 0.25)
            : nil
        let clusterMax = expectedValues.count >= Self.minimumExpectedCount
            ? percentile(expectedSorted, fraction: 0.75)
            : nil

        let averageDeltaAmount = offerDeltas.count >= Self.minimumAskOfferOverlap
            ? Int((Double(offerDeltas.map(\.amount).reduce(0, +)) / Double(offerDeltas.count)).rounded())
            : nil
        let averageDeltaPercent = offerDeltas.count >= Self.minimumAskOfferOverlap
            ? offerDeltas.map(\.percent).reduce(0, +) / Double(offerDeltas.count)
            : nil

        let latestDate = (expectedValues.map(\.date) + offerDeltas.map(\.date)).max()
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -Self.staleWindowDays, to: Date()) ?? Date()
        let isStale = latestDate.map { $0 < staleCutoff } ?? false

        return PersonalSalaryAnalyticsResult(
            baseCurrency: baseCurrency,
            expectedDataPointCount: expectedValues.count,
            expectedClusterMin: clusterMin,
            expectedClusterMax: clusterMax,
            askOfferOverlapCount: offerDeltas.count,
            averageOfferDeltaAmount: averageDeltaAmount,
            averageOfferDeltaPercent: averageDeltaPercent,
            summaryText: summaryText(
                baseCurrency: baseCurrency,
                clusterMin: clusterMin,
                clusterMax: clusterMax,
                averageDeltaAmount: averageDeltaAmount,
                averageDeltaPercent: averageDeltaPercent
            ),
            latestCompensationDate: latestDate,
            isStale: isStale
        )
    }

    private func midpoint(min: Int?, max: Int?) -> Int? {
        switch (min, max) {
        case let (min?, max?):
            return Int(((Double(min) + Double(max)) / 2.0).rounded())
        case let (min?, nil):
            return min
        case let (nil, max?):
            return max
        case (nil, nil):
            return nil
        }
    }

    private func percentile(_ sortedValues: [Int], fraction: Double) -> Int? {
        guard !sortedValues.isEmpty else { return nil }
        let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
        return sortedValues[index]
    }

    private func summaryText(
        baseCurrency: Currency,
        clusterMin: Int?,
        clusterMax: Int?,
        averageDeltaAmount: Int?,
        averageDeltaPercent: Double?
    ) -> String? {
        if let clusterMin, let clusterMax, let averageDeltaPercent {
            let direction = averageDeltaPercent >= 0 ? "above" : "below"
            return "Your expected compensation clusters around \(baseCurrency.format(clusterMin))-\(baseCurrency.format(clusterMax)). Recent offers have landed \(Int(abs(averageDeltaPercent).rounded()))% \(direction) your average ask."
        }

        if let clusterMin, let clusterMax {
            return "Your expected compensation clusters around \(baseCurrency.format(clusterMin))-\(baseCurrency.format(clusterMax))."
        }

        if let averageDeltaAmount, let averageDeltaPercent {
            let direction = averageDeltaPercent >= 0 ? "above" : "below"
            return "Recent offers have landed \(Int(abs(averageDeltaPercent).rounded()))% \(direction) your average ask, or about \(baseCurrency.format(abs(averageDeltaAmount)))."
        }

        return nil
    }

    private func convertValue(
        _ amount: Int,
        from: Currency,
        to: Currency,
        on date: Date,
        rateCache: inout [String: ExchangeRateService.ConversionResult?]
    ) async -> ExchangeRateService.ConversionResult? {
        if from == to {
            return ExchangeRateService.ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }

        let cacheKey = "\(from.rawValue)-\(to.rawValue)-\(normalizedDayKey(for: date))"
        let cached = rateCache[cacheKey]
        let conversion: ExchangeRateService.ConversionResult?

        if let cached {
            conversion = cached
        } else {
            let fetched = await exchangeRateService.convert(amount: 1, from: from, to: to, on: date)
            rateCache[cacheKey] = fetched
            conversion = fetched
        }

        guard let conversion else { return nil }
        return ExchangeRateService.ConversionResult(
            amount: conversion.amount * Double(amount),
            rateDate: conversion.rateDate,
            usedFallback: conversion.usedFallback
        )
    }

    private func normalizedDayKey(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }
}
