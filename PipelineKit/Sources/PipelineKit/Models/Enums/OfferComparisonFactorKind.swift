import Foundation

public enum OfferComparisonFactorKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case baseSalary
    case equity4Year
    case signingBonus
    case totalCompYear1
    case pto
    case remotePolicy
    case growthScore
    case teamCultureFit
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .baseSalary:
            return "Base Salary"
        case .equity4Year:
            return "Equity (4yr est.)"
        case .signingBonus:
            return "Signing Bonus"
        case .totalCompYear1:
            return "Total Comp (Year 1)"
        case .pto:
            return "PTO"
        case .remotePolicy:
            return "Remote Policy"
        case .growthScore:
            return "Growth Score"
        case .teamCultureFit:
            return "Team/Culture Fit"
        case .custom:
            return "Custom Factor"
        }
    }

    public var usesApplicationBackedScore: Bool {
        switch self {
        case .pto, .remotePolicy, .growthScore, .teamCultureFit:
            return true
        case .baseSalary, .equity4Year, .signingBonus, .totalCompYear1, .custom:
            return false
        }
    }

    public var isCompensation: Bool {
        switch self {
        case .baseSalary, .equity4Year, .signingBonus, .totalCompYear1:
            return true
        case .pto, .remotePolicy, .growthScore, .teamCultureFit, .custom:
            return false
        }
    }

    public static var builtInCases: [OfferComparisonFactorKind] {
        [
            .baseSalary,
            .equity4Year,
            .signingBonus,
            .totalCompYear1,
            .pto,
            .remotePolicy,
            .growthScore,
            .teamCultureFit
        ]
    }
}
