import Foundation
import SwiftData

public struct InterviewLearningResult {
    public let snapshot: InterviewLearningSnapshot
    public let usage: AIUsageMetrics?

    public init(snapshot: InterviewLearningSnapshot, usage: AIUsageMetrics?) {
        self.snapshot = snapshot
        self.usage = usage
    }
}

public enum InterviewLearningService {
    public static func generateSnapshot(
        provider: AIProvider,
        apiKey: String,
        model: String,
        applications: [JobApplication],
        in modelContext: ModelContext
    ) async throws -> InterviewLearningResult {
        let builder = InterviewLearningContextBuilder()
        let context = builder.build(from: applications)

        guard context.questionCount > 0 else {
            let fallback = builder.fallbackInsights(from: context)
            let persisted = try persist(snapshot: fallback, in: modelContext)
            return InterviewLearningResult(snapshot: persisted, usage: nil)
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(for: context)
        )

        let payload = try parseResponse(response.text)
        let snapshot = InterviewLearningSnapshot(
            strengths: payload.strengths,
            growthAreas: payload.growthAreas,
            recurringThemes: payload.recurringThemes,
            companyPatterns: payload.companyPatterns,
            recommendedFocusAreas: payload.recommendedFocusAreas,
            interviewCount: context.interviewCount,
            debriefCount: context.debriefCount,
            questionCount: context.questionCount,
            companyCount: context.companyCount,
            generatedAt: Date()
        )

        let persisted = try persist(snapshot: snapshot, in: modelContext)
        return InterviewLearningResult(snapshot: persisted, usage: response.usage)
    }

    static func userPrompt(for context: InterviewLearningContext) -> String {
        """
        Analyze this interview history and summarize durable learning patterns for the candidate.

        Context:
        \(context.learningSummary)

        Totals:
        - Interviews logged: \(context.interviewCount)
        - Debriefs completed: \(context.debriefCount)
        - Question bank entries: \(context.questionCount)
        - Companies represented: \(context.companyCount)
        """
    }

    static func parseResponse(_ rawJSON: String) throws -> LearningPayload {
        let cleaned = stripMarkdownFences(from: rawJSON)
        let candidate = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = candidate.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Interview learnings response was not valid JSON.")
        }

        return LearningPayload(
            strengths: parseStringArray(in: json, keys: ["strengths"]),
            growthAreas: parseStringArray(in: json, keys: ["growthAreas", "growth_areas"]),
            recurringThemes: parseStringArray(in: json, keys: ["recurringThemes", "recurring_themes"]),
            companyPatterns: parseStringArray(in: json, keys: ["companyPatterns", "company_patterns"]),
            recommendedFocusAreas: parseStringArray(in: json, keys: ["recommendedFocusAreas", "recommended_focus_areas"])
        )
    }

    @discardableResult
    private static func persist(
        snapshot: InterviewLearningSnapshot,
        in modelContext: ModelContext
    ) throws -> InterviewLearningSnapshot {
        let descriptor = FetchDescriptor<InterviewLearningSnapshot>()
        let existing = try modelContext.fetch(descriptor)
            .sorted { $0.generatedAt > $1.generatedAt }
            .first

        if let existing {
            existing.update(
                strengths: snapshot.strengths,
                growthAreas: snapshot.growthAreas,
                recurringThemes: snapshot.recurringThemes,
                companyPatterns: snapshot.companyPatterns,
                recommendedFocusAreas: snapshot.recommendedFocusAreas,
                interviewCount: snapshot.interviewCount,
                debriefCount: snapshot.debriefCount,
                questionCount: snapshot.questionCount,
                companyCount: snapshot.companyCount,
                generatedAt: snapshot.generatedAt
            )
            try modelContext.save()
            return existing
        }

        modelContext.insert(snapshot)
        try modelContext.save()
        return snapshot
    }

    private static let systemPrompt = """
    You are an interview coach analyzing a candidate's real interview debrief history.

    Return exactly one valid JSON object with this schema:
    {
      "strengths": [string],
      "growthAreas": [string],
      "recurringThemes": [string],
      "companyPatterns": [string],
      "recommendedFocusAreas": [string]
    }

    Rules:
    - Each array should contain 2-5 concise, specific bullets.
    - Use only evidence from the provided history. Do not invent facts or company behavior not supported by the notes.
    - Focus on actionable patterns, not generic interview advice.
    - Output raw JSON only.
    """

    struct LearningPayload {
        let strengths: [String]
        let growthAreas: [String]
        let recurringThemes: [String]
        let companyPatterns: [String]
        let recommendedFocusAreas: [String]
    }

    private static func parseStringArray(in json: [String: Any], keys: [String]) -> [String] {
        for key in keys {
            if let values = json[key] as? [String] {
                return values
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
        }
        return []
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
            } else if character == "{" {
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
