import Foundation

public enum SeniorityBand: String, Codable, CaseIterable, Identifiable, Sendable {
    case intern = "intern"
    case junior = "junior"
    case mid = "mid"
    case senior = "senior"
    case staff = "staff"
    case leadership = "leadership"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .intern:
            return "Intern"
        case .junior:
            return "Junior"
        case .mid:
            return "Mid"
        case .senior:
            return "Senior"
        case .staff:
            return "Staff+"
        case .leadership:
            return "Leadership"
        }
    }

    public static func inferred(from roleTitle: String) -> SeniorityBand? {
        let normalized = normalizedRoleTitle(from: roleTitle)
        guard !normalized.isEmpty else { return nil }

        if containsAny(normalized, patterns: ["intern", "apprentice", "trainee"]) {
            return .intern
        }
        if containsAny(normalized, patterns: ["junior", "jr", "associate", "entry level", "entry"]) {
            return .junior
        }
        if containsAny(normalized, patterns: [
            "director", "head", "vice president", "vp", "chief", "engineering manager"
        ]) {
            return .leadership
        }
        if containsAny(normalized, patterns: ["staff", "principal", "distinguished", "fellow"]) {
            return .staff
        }
        if containsAny(normalized, patterns: ["senior", "sr", "lead"]) {
            return .senior
        }
        if containsAny(normalized, patterns: [
            "engineer", "developer", "designer", "scientist", "analyst", "manager",
            "architect", "consultant", "administrator", "specialist", "researcher"
        ]) {
            return .mid
        }

        return nil
    }

    public static func normalizedRoleFamily(from roleTitle: String) -> String {
        var normalized = normalizedRoleTitle(from: roleTitle)
        let patterns = [
            "\\b(intern|apprentice|trainee|junior|jr|associate|entry level|entry|mid level|mid|senior|sr|lead|staff|principal|distinguished|fellow|director|head|vice president|vp|chief)\\b",
            "\\bl\\d+\\b",
            "\\b(level|grade)\\s*\\d+\\b",
            "\\b(i|ii|iii|iv|v|vi)\\b"
        ]

        for pattern in patterns {
            normalized = normalized.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        return normalized
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func normalizedRoleTitle(from roleTitle: String) -> String {
        roleTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAny(_ normalized: String, patterns: [String]) -> Bool {
        patterns.contains { pattern in
            let regex = "\\b" + NSRegularExpression.escapedPattern(for: pattern).replacingOccurrences(of: "\\ ", with: "\\s+") + "\\b"
            return normalized.range(of: regex, options: .regularExpression) != nil
        }
    }
}
