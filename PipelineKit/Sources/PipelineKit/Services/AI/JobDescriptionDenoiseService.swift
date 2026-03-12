import Foundation

public struct JobDescriptionDenoiseResult: Sendable, Equatable {
    public let cleanedDescription: String
    public let usage: AIUsageMetrics?

    public init(cleanedDescription: String, usage: AIUsageMetrics? = nil) {
        self.cleanedDescription = cleanedDescription
        self.usage = usage
    }
}

public enum JobDescriptionDenoiseService {
    public static func denoiseDescription(
        provider: AIProvider,
        apiKey: String,
        model: String,
        description: String
    ) async throws -> JobDescriptionDenoiseResult {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDescription.isEmpty else {
            throw AIServiceError.parsingError("Job description is empty.")
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: AIServicePrompts.jobDescriptionDenoisePrompt,
            userPrompt: AIServicePrompts.jobDescriptionDenoiseUserPrompt(
                description: String(trimmedDescription.prefix(8_000))
            )
        )

        return try parseResponse(response.text, usage: response.usage)
    }

    static func parseResponse(_ rawJSON: String, usage: AIUsageMetrics?) throws -> JobDescriptionDenoiseResult {
        let cleaned = stripMarkdownFences(from: rawJSON)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let extracted = extractJSONObject(from: cleaned),
               let data = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return try buildResult(from: json, usage: usage)
            }
            throw AIServiceError.parsingError("Job description denoise response was not valid JSON.")
        }

        return try buildResult(from: json, usage: usage)
    }

    private static func buildResult(
        from json: [String: Any],
        usage: AIUsageMetrics?
    ) throws -> JobDescriptionDenoiseResult {
        let cleanedDescription = (
            json["cleanedDescription"] as? String ??
            json["cleaned_description"] as? String ??
            json["jobDescription"] as? String ??
            json["job_description"] as? String
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !cleanedDescription.isEmpty else {
            throw AIServiceError.parsingError("Job description denoise response did not include cleanedDescription.")
        }

        return JobDescriptionDenoiseResult(
            cleanedDescription: cleanedDescription,
            usage: usage
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
