import Foundation

public enum ATSKeywordKind: String, Codable, CaseIterable, Sendable {
    case hardSkill = "hard_skill"
    case tool = "tool"
    case platform = "platform"
    case domain = "domain"
    case roleConcept = "role_concept"
}

public enum ATSKeywordImportance: String, Codable, CaseIterable, Sendable {
    case core = "core"
    case supporting = "supporting"
}

public struct ATSKeywordCandidate: Sendable, Equatable, Codable {
    public let term: String
    public let aliases: [String]
    public let kind: ATSKeywordKind
    public let importance: ATSKeywordImportance

    public init(
        term: String,
        aliases: [String] = [],
        kind: ATSKeywordKind,
        importance: ATSKeywordImportance
    ) {
        self.term = term
        self.aliases = aliases
        self.kind = kind
        self.importance = importance
    }
}

public struct ATSKeywordExtractionResult: Sendable, Equatable {
    public let keywords: [ATSKeywordCandidate]
    public let usage: AIUsageMetrics?

    public init(keywords: [ATSKeywordCandidate], usage: AIUsageMetrics? = nil) {
        self.keywords = keywords
        self.usage = usage
    }
}

public enum ATSKeywordExtractionService {
    private static let responseMaxTokens = 4_000

    private struct ResponseKeyword: Decodable {
        let term: String?
        let aliases: [String]?
        let kind: String?
        let importance: String?
        let keyword: String?
        let phrase: String?
    }

    private struct ResponsePayload: Decodable {
        let keywords: [ResponseKeyword]?
    }

    private static let bannedTerms: Set<String> = [
        "they", "them", "their", "theirs", "we", "our", "ours", "us",
        "you", "your", "yours", "company", "employer", "candidate", "applicant"
    ]

    public static func extractKeywords(
        provider: AIProvider,
        apiKey: String,
        model: String,
        companyName: String,
        role: String,
        jobDescription: String
    ) async throws -> ATSKeywordExtractionResult {
        let trimmedDescription = jobDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw AIServiceError.parsingError("Job description is empty.")
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: AIServicePrompts.atsKeywordExtractionPrompt,
            userPrompt: AIServicePrompts.atsKeywordExtractionUserPrompt(
                companyName: companyName,
                role: role,
                jobDescription: String(trimmedDescription.prefix(8_000))
            ),
            maxTokens: responseMaxTokens,
            temperature: 0.1
        )

        return try parseResponse(
            response.text,
            companyName: companyName,
            usage: response.usage
        )
    }

    static func parseResponse(
        _ rawJSON: String,
        companyName: String,
        usage: AIUsageMetrics?
    ) throws -> ATSKeywordExtractionResult {
        let cleaned = stripMarkdownFences(from: rawJSON)
        let payloadText = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = payloadText.data(using: .utf8) else {
            throw AIServiceError.parsingError("ATS keyword extraction response was not valid JSON.")
        }

        let payload: ResponsePayload
        do {
            payload = try JSONDecoder().decode(ResponsePayload.self, from: data)
        } catch {
            throw AIServiceError.parsingError("ATS keyword extraction response was not valid JSON.")
        }

        let keywords = sanitizeKeywords(
            payload.keywords ?? [],
            companyName: companyName
        )

        guard !keywords.isEmpty else {
            throw AIServiceError.parsingError("ATS keyword extraction returned no usable keywords.")
        }

        return ATSKeywordExtractionResult(
            keywords: keywords,
            usage: usage
        )
    }

    private static func sanitizeKeywords(
        _ keywords: [ResponseKeyword],
        companyName: String
    ) -> [ATSKeywordCandidate] {
        let normalizedCompany = normalizedTerm(companyName)
        var seen = Set<String>()
        var sanitized: [ATSKeywordCandidate] = []

        for rawKeyword in keywords {
            guard sanitized.count < 12 else { break }

            let rawTerm = (
                rawKeyword.term ??
                rawKeyword.keyword ??
                rawKeyword.phrase ??
                ""
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !rawTerm.isEmpty else { continue }

            let normalized = normalizedTerm(rawTerm)
            guard !normalized.isEmpty else { continue }
            guard !bannedTerms.contains(normalized) else { continue }
            guard normalized != normalizedCompany else { continue }
            guard seen.insert(normalized).inserted else { continue }

            guard let kind = normalizedKind(from: rawKeyword.kind),
                  let importance = normalizedImportance(from: rawKeyword.importance) else {
                continue
            }

            let aliases = sanitizeAliases(
                rawKeyword.aliases ?? [],
                term: rawTerm,
                companyName: companyName
            )

            sanitized.append(
                ATSKeywordCandidate(
                    term: rawTerm,
                    aliases: aliases,
                    kind: kind,
                    importance: importance
                )
            )
        }

        return sanitized
    }

    private static func sanitizeAliases(
        _ aliases: [String],
        term: String,
        companyName: String
    ) -> [String] {
        let normalizedCompany = normalizedTerm(companyName)
        let normalizedTermValue = normalizedTerm(term)
        var seen = Set<String>()
        var sanitized: [String] = []

        for alias in aliases {
            let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let normalized = normalizedTerm(trimmed)
            guard !normalized.isEmpty else { continue }
            guard normalized != normalizedTermValue else { continue }
            guard normalized != normalizedCompany else { continue }
            guard !bannedTerms.contains(normalized) else { continue }
            guard seen.insert(normalized).inserted else { continue }

            sanitized.append(trimmed)
        }

        return sanitized
    }

    private static func normalizedKind(from rawValue: String?) -> ATSKeywordKind? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        return normalized.flatMap(ATSKeywordKind.init(rawValue:))
    }

    private static func normalizedImportance(from rawValue: String?) -> ATSKeywordImportance? {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")

        return normalized.flatMap(ATSKeywordImportance.init(rawValue:))
    }

    private static func normalizedTerm(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func stripMarkdownFences(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(
            of: #"^```[a-zA-Z0-9_-]*\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*```$"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false

        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
