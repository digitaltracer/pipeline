import Foundation

public enum ResumeTailoringService {
    public static func generateSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String
    ) async throws -> ResumeTailoringResult {
        let raw = try await AICompletionClient.complete(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: ResumeTailoringPrompts.systemPrompt,
            userPrompt: ResumeTailoringPrompts.userPrompt(
                resumeJSON: resumeJSON,
                company: company,
                role: role,
                jobDescription: jobDescription
            )
        )

        return try parseResult(from: raw)
    }

    public static func parseResult(from rawResponse: String) throws -> ResumeTailoringResult {
        let cleaned = stripMarkdownFences(from: rawResponse)

        if let data = cleaned.data(using: .utf8),
           let direct = try? decodeResult(data: data) {
            return direct
        }

        if let extracted = extractJSONObject(from: cleaned),
           let data = extracted.data(using: .utf8),
           let parsed = try? decodeResult(data: data) {
            return parsed
        }

        throw AIServiceError.parsingError("Resume tailoring response was not valid JSON.")
    }

    private struct RawResult: Decodable {
        struct RawPatch: Decodable {
            let id: String?
            let path: String
            let operation: ResumePatch.Operation
            let beforeValue: JSONValue?
            let afterValue: JSONValue?
            let reason: String
            let evidencePaths: [String]?
            let risk: ResumePatch.Risk?
        }

        let patches: [RawPatch]
        let sectionGaps: [String]?
    }

    private static func decodeResult(data: Data) throws -> ResumeTailoringResult {
        let raw = try JSONDecoder().decode(RawResult.self, from: data)
        let patches = raw.patches.map { item in
            ResumePatch(
                id: item.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                path: item.path,
                operation: item.operation,
                beforeValue: item.beforeValue,
                afterValue: item.afterValue,
                reason: item.reason,
                evidencePaths: item.evidencePaths ?? [],
                risk: item.risk ?? .medium
            )
        }

        return ResumeTailoringResult(
            patches: patches,
            sectionGaps: raw.sectionGaps ?? []
        )
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
            let ch = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                continue
            }

            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
