import Foundation

// MARK: - Result Type

public struct InterviewPrepResult: Sendable {
    public let likelyQuestions: [String]
    public let talkingPoints: [String]
    public let companyResearchSummary: String
    public let usage: AIUsageMetrics?

    public init(
        likelyQuestions: [String],
        talkingPoints: [String],
        companyResearchSummary: String,
        usage: AIUsageMetrics? = nil
    ) {
        self.likelyQuestions = likelyQuestions
        self.talkingPoints = talkingPoints
        self.companyResearchSummary = companyResearchSummary
        self.usage = usage
    }
}

// MARK: - Service

public enum InterviewPrepService {

    public static func generatePrep(
        provider: AIProvider,
        apiKey: String,
        model: String,
        role: String,
        company: String,
        jobDescription: String,
        interviewStage: String,
        notes: String
    ) async throws -> InterviewPrepResult {
        let systemPrompt = """
        You are an expert career coach and interview preparation specialist.

        Return exactly one valid JSON object with this schema:
        {
          "likelyQuestions": [string],
          "talkingPoints": [string],
          "companyResearchSummary": string
        }

        Rules:
        - likelyQuestions: 8-12 specific interview questions the candidate is likely to face, tailored to the role, company, and interview stage. Include a mix of behavioral, technical, and role-specific questions.
        - talkingPoints: 5-8 concise talking points the candidate should prepare, based on the job description and their notes. Each should be actionable and specific.
        - companyResearchSummary: A 150-250 word summary of key company information the candidate should know, including recent news, culture, products, and competitive position. If you don't have specific company data, provide guidance on what to research.
        - Tailor the content to the interview stage (e.g., phone screen vs. final round).
        - Output raw JSON only. No markdown fences. No prose outside the JSON.
        """

        var userContext = "Role: \(role)\nCompany: \(company)"
        if !jobDescription.isEmpty {
            userContext += "\n\nJob Description:\n\(String(jobDescription.prefix(3000)))"
        }
        if !interviewStage.isEmpty {
            userContext += "\n\nInterview Stage: \(interviewStage)"
        }
        if !notes.isEmpty {
            userContext += "\n\nCandidate Notes:\n\(String(notes.prefix(1000)))"
        }

        let userPrompt = "Prepare interview prep materials for this opportunity:\n\n\(userContext)"

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

    private static func parseResponse(_ rawJSON: String, usage: AIUsageMetrics?) throws -> InterviewPrepResult {
        let cleaned = stripMarkdownFences(from: rawJSON)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Try extracting JSON object from mixed text
            if let extracted = extractJSONObject(from: cleaned),
               let data = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return buildResult(from: json, usage: usage)
            }
            throw AIServiceError.parsingError("Interview prep response was not valid JSON.")
        }

        return buildResult(from: json, usage: usage)
    }

    private static func buildResult(from json: [String: Any], usage: AIUsageMetrics?) -> InterviewPrepResult {
        let questions = (json["likelyQuestions"] as? [String])
            ?? (json["likely_questions"] as? [String])
            ?? (json["questions"] as? [String])
            ?? []

        let talkingPoints = (json["talkingPoints"] as? [String])
            ?? (json["talking_points"] as? [String])
            ?? (json["points"] as? [String])
            ?? []

        let summary = (json["companyResearchSummary"] as? String)
            ?? (json["company_research_summary"] as? String)
            ?? (json["companySummary"] as? String)
            ?? (json["company_summary"] as? String)
            ?? ""

        return InterviewPrepResult(
            likelyQuestions: questions,
            talkingPoints: talkingPoints,
            companyResearchSummary: summary,
            usage: usage
        )
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
