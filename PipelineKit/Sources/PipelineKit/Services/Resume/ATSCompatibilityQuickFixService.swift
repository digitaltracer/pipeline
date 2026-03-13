import Foundation

public struct ATSCompatibilityQuickFixResult: Sendable, Equatable {
    public let patches: [ResumePatch]
    public let unsupportedKeywords: [String]

    public init(patches: [ResumePatch], unsupportedKeywords: [String]) {
        self.patches = patches
        self.unsupportedKeywords = unsupportedKeywords
    }
}

public enum ATSCompatibilityQuickFixService {
    public static func makeSkillPromotionPatches(
        assessment: ATSCompatibilityAssessment,
        resumeJSON: String
    ) throws -> ATSCompatibilityQuickFixResult {
        let validation = try ResumeSchemaValidator.validate(jsonText: resumeJSON)
        let resume = validation.schema

        var skills = resume.skills
        var patches: [ResumePatch] = []
        var unsupportedKeywords: [String] = []

        for keyword in assessment.skillsPromotionKeywords {
            let evidencePaths = ATSCompatibilityScoringService.evidencePaths(for: keyword, in: resume)
            guard !evidencePaths.isEmpty else {
                unsupportedKeywords.append(keyword)
                continue
            }

            let targetCategory = preferredCategory(for: keyword, existingCategories: Array(skills.keys))
            let existingValues = skills[targetCategory] ?? []
            if contains(keyword: keyword, in: existingValues) {
                continue
            }

            let updatedValues = existingValues + [keyword]
            let path = "/skills/\(escapedJSONPointerToken(targetCategory))"
            let operation: ResumePatch.Operation = skills[targetCategory] == nil ? .add : .replace
            let beforeValue: JSONValue? = skills[targetCategory].map { .array($0.map(JSONValue.string)) }
            let afterValue: JSONValue = .array(updatedValues.map(JSONValue.string))

            patches.append(
                ResumePatch(
                    path: path,
                    operation: operation,
                    beforeValue: beforeValue,
                    afterValue: afterValue,
                    reason: "Promote ATS keyword into Skills using existing resume evidence.",
                    evidencePaths: evidencePaths,
                    risk: .low
                )
            )

            skills[targetCategory] = updatedValues
        }

        return ATSCompatibilityQuickFixResult(
            patches: patches,
            unsupportedKeywords: unsupportedKeywords.sorted()
        )
    }

    private static func contains(keyword: String, in values: [String]) -> Bool {
        values.contains { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(keyword.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        }
    }

    private static func preferredCategory(for keyword: String, existingCategories: [String]) -> String {
        let kind = categoryKind(for: keyword)
        let normalizedExisting = existingCategories.reduce(into: [String: String]()) { result, category in
            result[normalize(category)] = category
        }

        let preferredNames = switch kind {
        case .platform:
            ["platforms", "cloud", "infrastructure", "devops", "tools", "technologies"]
        case .practice:
            ["practices", "concepts", "architecture", "technologies", "tools"]
        case .language:
            ["languages", "frameworks", "technologies", "tools"]
        case .technology:
            ["technologies", "frameworks", "apis", "protocols", "tools", "platforms"]
        }

        for preferred in preferredNames {
            if let category = normalizedExisting[preferred] {
                return category
            }
        }

        return switch kind {
        case .platform:
            "Platforms"
        case .practice:
            "Practices"
        case .language:
            "Languages"
        case .technology:
            "Technologies"
        }
    }

    private static func escapedJSONPointerToken(_ value: String) -> String {
        value
            .replacingOccurrences(of: "~", with: "~0")
            .replacingOccurrences(of: "/", with: "~1")
    }

    private static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func categoryKind(for keyword: String) -> SkillCategoryKind {
        let normalized = normalize(keyword)

        if [
            "aws", "gcp", "azure", "kubernetes", "terraform", "docker", "datadog",
            "prometheus", "grafana", "ansible"
        ].contains(normalized) {
            return .platform
        }

        if [
            "ci/cd", "microservices", "distributed systems", "system design", "machine learning"
        ].contains(normalized) {
            return .practice
        }

        if [
            "swift", "go", "java", "python", "c++", ".net"
        ].contains(normalized) {
            return .language
        }

        return .technology
    }
}

private enum SkillCategoryKind {
    case platform
    case practice
    case language
    case technology
}
