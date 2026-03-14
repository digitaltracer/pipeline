import Foundation

public struct OfferComparisonScoreResult: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let applicationID: UUID
    public let companyName: String
    public let role: String
    public let weightedScore: Double
    public let maxWeightedScore: Double
    public let weightedAverage: Double

    public init(
        applicationID: UUID,
        companyName: String,
        role: String,
        weightedScore: Double,
        maxWeightedScore: Double,
        weightedAverage: Double
    ) {
        self.id = applicationID
        self.applicationID = applicationID
        self.companyName = companyName
        self.role = role
        self.weightedScore = weightedScore
        self.maxWeightedScore = maxWeightedScore
        self.weightedAverage = weightedAverage
    }
}

public struct OfferComparisonEvaluation: Equatable, Sendable {
    public let activeFactorCount: Int
    public let missingScoreCount: Int
    public let results: [OfferComparisonScoreResult]

    public init(
        activeFactorCount: Int,
        missingScoreCount: Int,
        results: [OfferComparisonScoreResult]
    ) {
        self.activeFactorCount = activeFactorCount
        self.missingScoreCount = missingScoreCount
        self.results = results
    }

    public var isComplete: Bool {
        activeFactorCount > 0 && missingScoreCount == 0 && !results.isEmpty
    }

    public var recommendedApplicationID: UUID? {
        guard isComplete else { return nil }
        return results.first?.applicationID
    }
}

public struct OfferComparisonDisplayValue: Equatable, Sendable {
    public let text: String
    public let score: Int?

    public init(text: String, score: Int?) {
        self.text = text
        self.score = score
    }
}

public final class OfferComparisonScoringService: Sendable {
    public init() {}

    public func evaluate(
        worksheet: OfferComparisonWorksheet,
        applications: [JobApplication]
    ) -> OfferComparisonEvaluation {
        let selectedApplications = selectedApplications(for: worksheet, from: applications)
        let factors = worksheet.sortedFactors.filter(\.isEnabled)

        guard !selectedApplications.isEmpty else {
            return OfferComparisonEvaluation(activeFactorCount: factors.count, missingScoreCount: 0, results: [])
        }

        let maxWeightedScore = Double(factors.reduce(0) { $0 + $1.weight * 5 })
        var missingScoreCount = 0
        var results: [OfferComparisonScoreResult] = []

        for application in selectedApplications {
            var weightedScore = 0.0

            for factor in factors {
                if let score = score(for: factor, application: application) {
                    weightedScore += Double(score * factor.weight)
                } else {
                    missingScoreCount += 1
                }
            }

            let weightedAverage = maxWeightedScore > 0 ? weightedScore / maxWeightedScore * 5.0 : 0
            results.append(
                OfferComparisonScoreResult(
                    applicationID: application.id,
                    companyName: application.companyName,
                    role: application.role,
                    weightedScore: weightedScore,
                    maxWeightedScore: maxWeightedScore,
                    weightedAverage: weightedAverage
                )
            )
        }

        results.sort { lhs, rhs in
            if lhs.weightedScore != rhs.weightedScore {
                return lhs.weightedScore > rhs.weightedScore
            }
            if lhs.companyName != rhs.companyName {
                return lhs.companyName.localizedCaseInsensitiveCompare(rhs.companyName) == .orderedAscending
            }
            return lhs.role.localizedCaseInsensitiveCompare(rhs.role) == .orderedAscending
        }

        return OfferComparisonEvaluation(
            activeFactorCount: factors.count,
            missingScoreCount: missingScoreCount,
            results: results
        )
    }

    public func selectedApplications(
        for worksheet: OfferComparisonWorksheet,
        from applications: [JobApplication]
    ) -> [JobApplication] {
        let offeredByID = Dictionary(uniqueKeysWithValues: applications.map { ($0.id, $0) })
        return worksheet.selectedApplicationIDs.compactMap { offeredByID[$0] }
    }

    public func displayValue(
        for factor: OfferComparisonFactor,
        application: JobApplication
    ) -> OfferComparisonDisplayValue {
        switch factor.kind {
        case .baseSalary:
            return OfferComparisonDisplayValue(
                text: application.offerBaseCompensation.map(application.currency.format) ?? "—",
                score: factor.value(for: application.id)?.score
            )
        case .equity4Year:
            return OfferComparisonDisplayValue(
                text: application.offerEquityCompensation.map(application.currency.format) ?? "—",
                score: factor.value(for: application.id)?.score
            )
        case .signingBonus:
            return OfferComparisonDisplayValue(
                text: application.offerBonusCompensation.map(application.currency.format) ?? "—",
                score: factor.value(for: application.id)?.score
            )
        case .totalCompYear1:
            return OfferComparisonDisplayValue(
                text: application.offerYearOneTotalCompText ?? "—",
                score: factor.value(for: application.id)?.score
            )
        case .pto:
            return OfferComparisonDisplayValue(
                text: application.offerPTOText ?? "—",
                score: application.offerPTOScore
            )
        case .remotePolicy:
            return OfferComparisonDisplayValue(
                text: application.offerRemotePolicyText ?? "—",
                score: application.offerRemotePolicyScore
            )
        case .growthScore:
            return OfferComparisonDisplayValue(
                text: starText(for: application.offerGrowthScore),
                score: application.offerGrowthScore
            )
        case .teamCultureFit:
            return OfferComparisonDisplayValue(
                text: starText(for: application.offerTeamCultureFitScore),
                score: application.offerTeamCultureFitScore
            )
        case .custom:
            let value = factor.value(for: application.id)
            return OfferComparisonDisplayValue(text: value?.displayText ?? "—", score: value?.score)
        }
    }

    public func score(
        for factor: OfferComparisonFactor,
        application: JobApplication
    ) -> Int? {
        switch factor.kind {
        case .pto:
            return application.offerPTOScore
        case .remotePolicy:
            return application.offerRemotePolicyScore
        case .growthScore:
            return application.offerGrowthScore
        case .teamCultureFit:
            return application.offerTeamCultureFitScore
        case .baseSalary, .equity4Year, .signingBonus, .totalCompYear1, .custom:
            return factor.value(for: application.id)?.score
        }
    }

    public func starText(for score: Int?) -> String {
        guard let score, score > 0 else { return "—" }
        return String(repeating: "★", count: score)
    }
}
