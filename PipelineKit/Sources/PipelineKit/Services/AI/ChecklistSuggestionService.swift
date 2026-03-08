import Foundation

public struct ChecklistSuggestionCandidate: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let rationale: String

    public init(title: String, rationale: String) {
        self.title = title
        self.rationale = rationale
        self.id = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct ChecklistSuggestionResult: Sendable {
    public let suggestions: [ChecklistSuggestionCandidate]
    public let usage: AIUsageMetrics?

    public init(
        suggestions: [ChecklistSuggestionCandidate],
        usage: AIUsageMetrics? = nil
    ) {
        self.suggestions = suggestions
        self.usage = usage
    }
}

public enum ChecklistSuggestionService {
    public static func generateSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        application: JobApplication
    ) async throws -> ChecklistSuggestionResult {
        let systemPrompt = """
        You are helping a job candidate decide what to do next for one specific application.

        Return exactly one valid JSON object with this schema:
        {
          "suggestions": [
            {
              "title": string,
              "rationale": string
            }
          ]
        }

        Rules:
        - Return 3 to 5 suggestions.
        - Each title must be a concise, action-oriented next step under 80 characters.
        - Each rationale must be 1 to 2 short sentences explaining why that step matters for this role.
        - Suggestions must be tailored to the role, company, stage, and available notes.
        - Do not repeat generic base workflow items already covered elsewhere, including tailoring the resume, generating a cover letter, researching the company, finding a referral, submitting the application, following up, interview prep, researching interviewers, sending thank-you notes, comparing offers, or negotiating salary.
        - Prefer specific prep, story-building, portfolio, networking, or research tasks that are uniquely relevant to the opportunity.
        - Avoid duplicates or near-duplicates.
        - Output raw JSON only. No markdown fences. No prose outside the JSON.
        """

        let userPrompt = """
        Generate optional checklist suggestions for this application.

        \(applicationContext(for: application))
        """

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        return try parseResponse(response.text, usage: response.usage)
    }

    static func parseResponse(_ rawJSON: String, usage: AIUsageMetrics?) throws -> ChecklistSuggestionResult {
        let cleaned = stripMarkdownFences(from: rawJSON)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let extracted = extractJSONObject(from: cleaned),
               let data = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return buildResult(from: json, usage: usage)
            }
            throw AIServiceError.parsingError("Checklist suggestions response was not valid JSON.")
        }

        return buildResult(from: json, usage: usage)
    }

    private static func applicationContext(for application: JobApplication) -> String {
        var sections: [String] = [
            "Company: \(application.companyName)",
            "Role: \(application.role)",
            "Location: \(application.location)",
            "Status: \(application.status.displayName)"
        ]

        if let interviewStage = application.interviewStage?.displayName {
            sections.append("Interview Stage: \(interviewStage)")
        }

        if let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            sections.append("Job Description:\n\(String(description.prefix(3000)))")
        }

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Candidate Notes:\n\(String(overview.prefix(1400)))")
        }

        if let company = application.company {
            let researchSummary = company.lastResearchSummary ?? company.sortedResearchSnapshots.first?.summaryText
            if let researchSummary {
                let trimmedResearchSummary = researchSummary.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedResearchSummary.isEmpty {
                    sections.append("Company Research Summary:\n\(String(trimmedResearchSummary.prefix(1200)))")
                }
            }
        }

        let contactRoles = Set(application.sortedContactLinks.map(\.role.displayName))
        if !contactRoles.isEmpty {
            sections.append("Known Contacts: \(contactRoles.sorted().joined(separator: ", "))")
        }

        let existingTaskTitles = Set(application.sortedTasks.map(\.displayTitle))
        if !existingTaskTitles.isEmpty {
            sections.append("Existing Tasks:\n- \(existingTaskTitles.sorted().joined(separator: "\n- "))")
        }

        return sections.joined(separator: "\n\n")
    }

    private static func buildResult(from json: [String: Any], usage: AIUsageMetrics?) -> ChecklistSuggestionResult {
        let rawSuggestions = (json["suggestions"] as? [[String: Any]])
            ?? (json["items"] as? [[String: Any]])
            ?? []

        var seenTitles = Set<String>()
        let suggestions = rawSuggestions.compactMap { item -> ChecklistSuggestionCandidate? in
            let rawTitle = (item["title"] as? String) ?? (item["task"] as? String) ?? (item["name"] as? String) ?? ""
            let rawRationale = (item["rationale"] as? String) ?? (item["reason"] as? String) ?? (item["why"] as? String) ?? ""

            let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            let rationale = rawRationale.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty else { return nil }

            let normalizedTitle = title.lowercased()
            guard seenTitles.insert(normalizedTitle).inserted else { return nil }

            return ChecklistSuggestionCandidate(title: title, rationale: rationale)
        }

        return ChecklistSuggestionResult(suggestions: suggestions, usage: usage)
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
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
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
