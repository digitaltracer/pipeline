import CryptoKit
import Foundation

public enum JobMatchWorkMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case remote
    case hybrid
    case onSite = "on_site"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .remote:
            return "Remote"
        case .hybrid:
            return "Hybrid"
        case .onSite:
            return "On-site"
        }
    }
}

public struct JobMatchPreferences: Codable, Sendable, Equatable {
    public var preferredCurrency: Currency
    public var preferredSalaryMin: Int?
    public var preferredSalaryMax: Int?
    public var allowedWorkModes: [JobMatchWorkMode]
    public var preferredLocations: [String]

    public init(
        preferredCurrency: Currency = .usd,
        preferredSalaryMin: Int? = nil,
        preferredSalaryMax: Int? = nil,
        allowedWorkModes: [JobMatchWorkMode] = JobMatchWorkMode.allCases,
        preferredLocations: [String] = []
    ) {
        self.preferredCurrency = preferredCurrency
        self.preferredSalaryMin = preferredSalaryMin
        self.preferredSalaryMax = preferredSalaryMax
        self.allowedWorkModes = allowedWorkModes.uniquedPreservingOrder()
        self.preferredLocations = Self.normalizedLocations(preferredLocations)
    }

    public var normalizedAllowedWorkModes: [JobMatchWorkMode] {
        allowedWorkModes.uniquedPreservingOrder()
    }

    public var normalizedPreferredLocations: [String] {
        Self.normalizedLocations(preferredLocations)
    }

    public var fingerprint: String {
        let canonical = CanonicalFingerprint(
            preferredCurrency: preferredCurrency.rawValue,
            preferredSalaryMin: preferredSalaryMin,
            preferredSalaryMax: preferredSalaryMax,
            allowedWorkModes: normalizedAllowedWorkModes.map(\.rawValue).sorted(),
            preferredLocations: normalizedPreferredLocations.sorted()
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(canonical)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public var hasSalaryPreference: Bool {
        preferredSalaryMin != nil || preferredSalaryMax != nil
    }

    public var hasLocationPreference: Bool {
        !normalizedAllowedWorkModes.isEmpty || !normalizedPreferredLocations.isEmpty
    }

    private static func normalizedLocations(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniquedPreservingOrder()
    }

    private struct CanonicalFingerprint: Codable {
        let preferredCurrency: String
        let preferredSalaryMin: Int?
        let preferredSalaryMax: Int?
        let allowedWorkModes: [String]
        let preferredLocations: [String]
    }
}

private extension Array where Element: Equatable {
    func uniquedPreservingOrder() -> [Element] {
        var result: [Element] = []
        for value in self where !result.contains(value) {
            result.append(value)
        }
        return result
    }
}
