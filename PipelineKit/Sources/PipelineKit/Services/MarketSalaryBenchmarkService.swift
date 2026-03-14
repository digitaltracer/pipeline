import Foundation

public enum MarketSalaryComparisonBasis: String, Sendable {
    case posted = "posted"
    case expected = "expected"
    case offer = "offer"

    public var title: String {
        switch self {
        case .posted:
            return "Posted compensation"
        case .expected:
            return "Expected compensation"
        case .offer:
            return "Offer compensation"
        }
    }
}

public enum MarketSalaryMatchTier: String, Sendable {
    case exactRoleLocation = "exact_role_location"
    case exactRoleAnyLocation = "exact_role_any_location"
    case roleFamilyAnyLocation = "role_family_any_location"

    public var title: String {
        switch self {
        case .exactRoleLocation:
            return "Exact role, location, and seniority"
        case .exactRoleAnyLocation:
            return "Exact role and seniority"
        case .roleFamilyAnyLocation:
            return "Role family and seniority"
        }
    }
}

public enum MarketSalaryConfidence: String, Sendable {
    case high = "high"
    case medium = "medium"
    case low = "low"

    public var title: String { rawValue.capitalized }
}

public struct MarketSalarySourceCount: Identifiable, Sendable {
    public let id: String
    public let sourceName: String
    public let count: Int

    public init(sourceName: String, count: Int) {
        self.id = sourceName.lowercased()
        self.sourceName = sourceName
        self.count = count
    }
}

public struct MarketSalaryBenchmarkResult: Sendable {
    public let baseCurrency: Currency
    public let comparisonBasis: MarketSalaryComparisonBasis
    public let matchTier: MarketSalaryMatchTier
    public let confidence: MarketSalaryConfidence
    public let seniority: SeniorityBand
    public let cohortCount: Int
    public let internalApplicationCount: Int
    public let externalSnapshotCount: Int
    public let sourceCounts: [MarketSalarySourceCount]
    public let percentile25: Int
    public let percentile50: Int
    public let percentile75: Int
    public let currentCompensation: Int?
    public let deltaFromMedian: Int?
    public let deltaPercentFromMedian: Double?
    public let comparisonText: String
    public let missingConversionCount: Int
    public let lastRefreshedAt: Date?

    public init(
        baseCurrency: Currency,
        comparisonBasis: MarketSalaryComparisonBasis,
        matchTier: MarketSalaryMatchTier,
        confidence: MarketSalaryConfidence,
        seniority: SeniorityBand,
        cohortCount: Int,
        internalApplicationCount: Int,
        externalSnapshotCount: Int,
        sourceCounts: [MarketSalarySourceCount],
        percentile25: Int,
        percentile50: Int,
        percentile75: Int,
        currentCompensation: Int?,
        deltaFromMedian: Int?,
        deltaPercentFromMedian: Double?,
        comparisonText: String,
        missingConversionCount: Int,
        lastRefreshedAt: Date?
    ) {
        self.baseCurrency = baseCurrency
        self.comparisonBasis = comparisonBasis
        self.matchTier = matchTier
        self.confidence = confidence
        self.seniority = seniority
        self.cohortCount = cohortCount
        self.internalApplicationCount = internalApplicationCount
        self.externalSnapshotCount = externalSnapshotCount
        self.sourceCounts = sourceCounts
        self.percentile25 = percentile25
        self.percentile50 = percentile50
        self.percentile75 = percentile75
        self.currentCompensation = currentCompensation
        self.deltaFromMedian = deltaFromMedian
        self.deltaPercentFromMedian = deltaPercentFromMedian
        self.comparisonText = comparisonText
        self.missingConversionCount = missingConversionCount
        self.lastRefreshedAt = lastRefreshedAt
    }
}

public final class MarketSalaryBenchmarkService: @unchecked Sendable {
    public static let minimumCohortSize = 5

    private let exchangeRateService: ExchangeRateProviding

    public init(exchangeRateService: ExchangeRateProviding = ExchangeRateService.shared) {
        self.exchangeRateService = exchangeRateService
    }

    public func benchmark(
        for application: JobApplication,
        among applications: [JobApplication],
        salarySnapshots: [CompanySalarySnapshot],
        baseCurrency: Currency
    ) async -> MarketSalaryBenchmarkResult? {
        guard let seniority = application.effectiveSeniority else { return nil }

        let basis = preferredBasis(for: application)
        let normalizedRole = SeniorityBand.normalizedRoleTitle(from: application.role)
        let normalizedRoleFamily = application.normalizedRoleFamily
        let normalizedLocation = CompanyProfile.normalizedLocation(application.location)

        var rateCache: [String: ExchangeRateService.ConversionResult?] = [:]

        let tiers: [(MarketSalaryMatchTier, (Candidate) -> Bool)] = [
            (.exactRoleLocation, { candidate in
                candidate.normalizedRole == normalizedRole &&
                candidate.normalizedLocation == normalizedLocation &&
                candidate.seniority == seniority
            }),
            (.exactRoleAnyLocation, { candidate in
                candidate.normalizedRole == normalizedRole &&
                candidate.seniority == seniority
            }),
            (.roleFamilyAnyLocation, { candidate in
                candidate.normalizedRoleFamily == normalizedRoleFamily &&
                candidate.seniority == seniority
            })
        ]

        let internalCandidates = await makeInternalCandidates(
            currentApplication: application,
            applications: applications,
            basis: basis,
            baseCurrency: baseCurrency,
            rateCache: &rateCache
        )
        let externalCandidates = await makeExternalCandidates(
            salarySnapshots: salarySnapshots,
            baseCurrency: baseCurrency,
            rateCache: &rateCache
        )

        for (tier, matcher) in tiers {
            let internalMatches = internalCandidates.filter(matcher)
            let externalMatches = externalCandidates.filter(matcher)
            let allValues = (internalMatches + externalMatches).compactMap(\.value)
            guard allValues.count >= Self.minimumCohortSize else { continue }
            let internalValueCount = internalMatches.compactMap(\.value).count
            let externalValueCount = externalMatches.compactMap(\.value).count

            let sortedValues = allValues.sorted()
            let p25 = percentile(sortedValues, fraction: 0.25)
            let p50 = percentile(sortedValues, fraction: 0.5)
            let p75 = percentile(sortedValues, fraction: 0.75)
            let currentCompensation = await convertedCurrentCompensation(
                for: application,
                basis: basis,
                baseCurrency: baseCurrency,
                rateCache: &rateCache
            )
            let delta = currentCompensation.map { $0 - p50 }
            let deltaPercent: Double? = if let currentCompensation, p50 != 0 {
                (Double(currentCompensation - p50) / Double(p50)) * 100
            } else if currentCompensation != nil {
                0
            } else {
                nil
            }

            return MarketSalaryBenchmarkResult(
                baseCurrency: baseCurrency,
                comparisonBasis: basis,
                matchTier: tier,
                confidence: confidence(for: tier, cohortCount: allValues.count),
                seniority: seniority,
                cohortCount: allValues.count,
                internalApplicationCount: internalValueCount,
                externalSnapshotCount: externalValueCount,
                sourceCounts: sourceCounts(internalMatches: internalMatches, externalMatches: externalMatches),
                percentile25: p25,
                percentile50: p50,
                percentile75: p75,
                currentCompensation: currentCompensation,
                deltaFromMedian: delta,
                deltaPercentFromMedian: deltaPercent,
                comparisonText: comparisonText(
                    currentCompensation: currentCompensation,
                    delta: delta,
                    deltaPercent: deltaPercent,
                    median: p50,
                    currency: baseCurrency
                ),
                missingConversionCount: internalMatches.filter(\.wasMissingConversion).count + externalMatches.filter(\.wasMissingConversion).count,
                lastRefreshedAt: (internalMatches + externalMatches).map(\.capturedAt).max()
            )
        }

        return nil
    }

    private func preferredBasis(for application: JobApplication) -> MarketSalaryComparisonBasis {
        if application.offerTotalComp != nil {
            return .offer
        }
        if midpoint(min: application.expectedTotalCompMin, max: application.expectedTotalCompMax) != nil {
            return .expected
        }
        return .posted
    }

    private func makeInternalCandidates(
        currentApplication: JobApplication,
        applications: [JobApplication],
        basis: MarketSalaryComparisonBasis,
        baseCurrency: Currency,
        rateCache: inout [String: ExchangeRateService.ConversionResult?]
    ) async -> [Candidate] {
        var candidates: [Candidate] = []

        for application in applications where application.id != currentApplication.id {
            guard let seniority = application.effectiveSeniority else { continue }
            guard let rawValue = currentValue(for: application, basis: basis) else { continue }

            guard let converted = await convertValue(
                rawValue.amount,
                from: application.currency,
                to: baseCurrency,
                on: rawValue.date,
                rateCache: &rateCache
            ) else {
                candidates.append(
                    Candidate(
                        normalizedRole: SeniorityBand.normalizedRoleTitle(from: application.role),
                        normalizedRoleFamily: application.normalizedRoleFamily,
                        normalizedLocation: CompanyProfile.normalizedLocation(application.location),
                        seniority: seniority,
                        value: nil,
                        sourceName: "Pipeline",
                        capturedAt: rawValue.date,
                        wasMissingConversion: true
                    )
                )
                continue
            }

            candidates.append(
                Candidate(
                    normalizedRole: SeniorityBand.normalizedRoleTitle(from: application.role),
                    normalizedRoleFamily: application.normalizedRoleFamily,
                    normalizedLocation: CompanyProfile.normalizedLocation(application.location),
                    seniority: seniority,
                    value: Int(converted.amount.rounded()),
                    sourceName: "Pipeline",
                    capturedAt: rawValue.date,
                    wasMissingConversion: false
                )
            )
        }

        return candidates
    }

    private func makeExternalCandidates(
        salarySnapshots: [CompanySalarySnapshot],
        baseCurrency: Currency,
        rateCache: inout [String: ExchangeRateService.ConversionResult?]
    ) async -> [Candidate] {
        var candidates: [Candidate] = []

        for snapshot in salarySnapshots {
            guard let seniority = snapshot.effectiveSeniority else { continue }
            guard let midpoint = midpoint(
                min: snapshot.minTotalCompensation ?? snapshot.minBaseCompensation,
                max: snapshot.maxTotalCompensation ?? snapshot.maxBaseCompensation
            ) else {
                continue
            }

            guard let converted = await convertValue(
                midpoint,
                from: snapshot.currency,
                to: baseCurrency,
                on: snapshot.capturedAt,
                rateCache: &rateCache
            ) else {
                candidates.append(
                    Candidate(
                        normalizedRole: snapshot.normalizedRoleTitle,
                        normalizedRoleFamily: SeniorityBand.normalizedRoleFamily(from: snapshot.roleTitle),
                        normalizedLocation: snapshot.normalizedLocation,
                        seniority: seniority,
                        value: nil,
                        sourceName: snapshot.sourceName,
                        capturedAt: snapshot.capturedAt,
                        wasMissingConversion: true
                    )
                )
                continue
            }

            candidates.append(
                Candidate(
                    normalizedRole: snapshot.normalizedRoleTitle,
                    normalizedRoleFamily: SeniorityBand.normalizedRoleFamily(from: snapshot.roleTitle),
                    normalizedLocation: snapshot.normalizedLocation,
                    seniority: seniority,
                    value: Int(converted.amount.rounded()),
                    sourceName: snapshot.sourceName,
                    capturedAt: snapshot.capturedAt,
                    wasMissingConversion: false
                )
            )
        }

        return candidates
    }

    private func convertedCurrentCompensation(
        for application: JobApplication,
        basis: MarketSalaryComparisonBasis,
        baseCurrency: Currency,
        rateCache: inout [String: ExchangeRateService.ConversionResult?]
    ) async -> Int? {
        guard let current = currentValue(for: application, basis: basis) else { return nil }
        guard let converted = await convertValue(
            current.amount,
            from: application.currency,
            to: baseCurrency,
            on: current.date,
            rateCache: &rateCache
        ) else {
            return nil
        }
        return Int(converted.amount.rounded())
    }

    private func currentValue(
        for application: JobApplication,
        basis: MarketSalaryComparisonBasis
    ) -> (amount: Int, date: Date)? {
        switch basis {
        case .posted:
            guard let amount = midpoint(min: application.postedTotalCompMin, max: application.postedTotalCompMax) else {
                return nil
            }
            return (amount, application.submittedAt ?? application.updatedAt)
        case .expected:
            guard let amount = midpoint(min: application.expectedTotalCompMin, max: application.expectedTotalCompMax) else {
                return nil
            }
            return (amount, application.updatedAt)
        case .offer:
            guard let amount = application.offerTotalComp else { return nil }
            return (amount, application.updatedAt)
        }
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

    private func percentile(_ sortedValues: [Int], fraction: Double) -> Int {
        guard !sortedValues.isEmpty else { return 0 }
        let index = Int((Double(sortedValues.count - 1) * fraction).rounded())
        return sortedValues[index]
    }

    private func comparisonText(
        currentCompensation: Int?,
        delta: Int?,
        deltaPercent: Double?,
        median: Int,
        currency: Currency
    ) -> String {
        guard let currentCompensation, let delta, let deltaPercent else {
            return "Median market compensation is \(currency.format(median))."
        }

        let roundedPercent = Int(abs(deltaPercent).rounded())
        if delta == 0 {
            return "Your current compensation is aligned with the median market level at \(currency.format(currentCompensation))."
        }

        let direction = delta > 0 ? "above" : "below"
        return "Your current compensation is \(roundedPercent)% \(direction) median."
    }

    private func confidence(for tier: MarketSalaryMatchTier, cohortCount: Int) -> MarketSalaryConfidence {
        switch tier {
        case .exactRoleLocation:
            return cohortCount >= 10 ? .high : .medium
        case .exactRoleAnyLocation:
            return .medium
        case .roleFamilyAnyLocation:
            return .low
        }
    }

    private func sourceCounts(
        internalMatches: [Candidate],
        externalMatches: [Candidate]
    ) -> [MarketSalarySourceCount] {
        var counts: [String: Int] = [:]
        let internalCount = internalMatches.compactMap(\.value).count
        if internalCount > 0 {
            counts["Pipeline"] = internalCount
        }
        for candidate in externalMatches {
            guard candidate.value != nil else { continue }
            counts[candidate.sourceName, default: 0] += 1
        }

        return counts
            .filter { $0.value > 0 }
            .map { MarketSalarySourceCount(sourceName: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.sourceName.localizedCaseInsensitiveCompare(rhs.sourceName) == .orderedAscending
            }
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

    private struct Candidate: Sendable {
        let normalizedRole: String
        let normalizedRoleFamily: String
        let normalizedLocation: String
        let seniority: SeniorityBand
        let value: Int?
        let sourceName: String
        let capturedAt: Date
        let wasMissingConversion: Bool
    }
}
