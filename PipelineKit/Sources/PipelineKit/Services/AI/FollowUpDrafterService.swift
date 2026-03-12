import Foundation

// MARK: - Result Type

public struct FollowUpEmailResult: Sendable {
    public let subject: String
    public let body: String
    public let usage: AIUsageMetrics?

    public init(subject: String, body: String, usage: AIUsageMetrics? = nil) {
        self.subject = subject
        self.body = body
        self.usage = usage
    }
}

// MARK: - Service

public enum FollowUpDrafterService {

    public static func generateFollowUp(
        provider: AIProvider,
        apiKey: String,
        model: String,
        company: String,
        role: String,
        stage: String,
        notes: String,
        daysSinceLastContact: Int
    ) async throws -> FollowUpEmailResult {
        let systemPrompt = """
        You are a professional career communications specialist who drafts follow-up emails for job applicants.

        Return exactly one valid JSON object with this schema:
        {
          "subject": string,
          "body": string
        }

        Rules:
        - subject: A concise, professional email subject line for a follow-up email.
        - body: A professional 150-250 word follow-up email body. Do NOT include a subject line in the body. Start with a greeting (e.g., "Dear Hiring Team,") and end with a professional sign-off (e.g., "Best regards,\n[Your Name]").
        - The tone should be polite, professional, and express continued interest without being pushy.
        - Reference the specific role and company naturally.
        - If days since last contact is provided, acknowledge the passage of time appropriately.
        - If interview notes are provided, reference specific topics or conversations.
        - Output raw JSON only. No markdown fences. No prose outside the JSON.
        """

        var userContext = "Company: \(company)\nRole: \(role)"
        if !stage.isEmpty {
            userContext += "\nCurrent Stage: \(stage)"
        }
        if daysSinceLastContact > 0 {
            userContext += "\nDays Since Last Contact: \(daysSinceLastContact)"
        }
        if !notes.isEmpty {
            userContext += "\n\nInterview/Application Notes:\n\(String(notes.prefix(1500)))"
        }

        let userPrompt = "Draft a follow-up email for this job application:\n\n\(userContext)"

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        return try parseResponse(response.text, usage: response.usage)
    }

    // MARK: - Parsing

    private static func parseResponse(_ rawJSON: String, usage: AIUsageMetrics?) throws -> FollowUpEmailResult {
        let cleaned = stripMarkdownFences(from: rawJSON)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let extracted = extractJSONObject(from: cleaned),
               let data = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return buildResult(from: json, usage: usage)
            }
            throw AIServiceError.parsingError("Follow-up email response was not valid JSON.")
        }

        return buildResult(from: json, usage: usage)
    }

    private static func buildResult(from json: [String: Any], usage: AIUsageMetrics?) -> FollowUpEmailResult {
        let subject = (json["subject"] as? String)
            ?? (json["email_subject"] as? String)
            ?? "Following Up on \(json["role"] as? String ?? "Application")"

        let body = (json["body"] as? String)
            ?? (json["email_body"] as? String)
            ?? (json["content"] as? String)
            ?? ""

        return FollowUpEmailResult(subject: subject, body: body, usage: usage)
    }

    private static func stripMarkdownFences(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(
            of: #"^```[a-zA-Z0-9_-]*\s*"#, with: "", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*```$"#, with: "", options: .regularExpression
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
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
                continue
            }
            if ch == "\"" { inString = true; continue }
            if ch == "{" { depth += 1 }
            else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(text[start...index]) }
            }
        }
        return nil
    }
}
