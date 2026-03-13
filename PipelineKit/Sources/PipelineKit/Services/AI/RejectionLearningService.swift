import Foundation
import SwiftData

public struct RejectionLearningResult {
    public let snapshot: RejectionLearningSnapshot
    public let usage: AIUsageMetrics?

    public init(snapshot: RejectionLearningSnapshot, usage: AIUsageMetrics?) {
        self.snapshot = snapshot
        self.usage = usage
    }
}

public enum RejectionLearningService {
    public static func generateSnapshot(
        provider: AIProvider,
        apiKey: String,
        model: String,
        applications: [JobApplication],
        in modelContext: ModelContext
    ) async throws -> RejectionLearningResult {
        let builder = RejectionLearningContextBuilder()
        let context = builder.build(from: applications)

        guard context.rejectionCount >= 3 else {
            throw AIServiceError.parsingError("At least 3 logged rejections are required before analysis is meaningful.")
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt(for: context)
        )

        let payload = try parseResponse(response.text)
        let snapshot = RejectionLearningSnapshot(
            patternSignals: payload.patternSignals,
            targetingSignals: payload.targetingSignals,
            processSignals: payload.processSignals,
            recoverySuggestions: payload.recoverySuggestions,
            stageCounts: context.stageCounts.map { "\($0.stage.displayName): \($0.count)" },
            reasonCounts: context.reasonCounts.map { "\($0.reason.displayName): \($0.count)" },
            feedbackSourceCounts: context.feedbackSourceCounts.map { "\($0.source.displayName): \($0.count)" },
            rejectionCount: context.rejectionCount,
            explicitFeedbackCount: context.explicitFeedbackCount,
            generatedAt: Date()
        )

        let persisted = try persist(snapshot: snapshot, in: modelContext)
        return RejectionLearningResult(snapshot: persisted, usage: response.usage)
    }

    static func userPrompt(for context: RejectionLearningContext) -> String {
        """
        Analyze these rejection logs and summarize actionable job-search patterns.

        Context:
        \(context.learningSummary)

        Totals:
        - Logged rejections: \(context.rejectionCount)
        - Explicit feedback count: \(context.explicitFeedbackCount)
        """
    }

    static func parseResponse(_ rawJSON: String) throws -> LearningPayload {
        let cleaned = stripMarkdownFences(from: rawJSON)
        let candidate = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = candidate.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Rejection learnings response was not valid JSON.")
        }

        return LearningPayload(
            patternSignals: parseStringArray(in: json, keys: ["patternSignals", "pattern_signals"]),
            targetingSignals: parseStringArray(in: json, keys: ["targetingSignals", "targeting_signals"]),
            processSignals: parseStringArray(in: json, keys: ["processSignals", "process_signals"]),
            recoverySuggestions: parseStringArray(in: json, keys: ["recoverySuggestions", "recovery_suggestions"])
        )
    }

    @discardableResult
    private static func persist(
        snapshot: RejectionLearningSnapshot,
        in modelContext: ModelContext
    ) throws -> RejectionLearningSnapshot {
        let descriptor = FetchDescriptor<RejectionLearningSnapshot>()
        let existing = try modelContext.fetch(descriptor)
            .sorted { $0.generatedAt > $1.generatedAt }
            .first

        if let existing {
            existing.update(
                patternSignals: snapshot.patternSignals,
                targetingSignals: snapshot.targetingSignals,
                processSignals: snapshot.processSignals,
                recoverySuggestions: snapshot.recoverySuggestions,
                stageCounts: snapshot.stageCounts,
                reasonCounts: snapshot.reasonCounts,
                feedbackSourceCounts: snapshot.feedbackSourceCounts,
                rejectionCount: snapshot.rejectionCount,
                explicitFeedbackCount: snapshot.explicitFeedbackCount,
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
    You are a job-search coach analyzing rejection logs.

    Return exactly one valid JSON object with this schema:
    {
      "patternSignals": [string],
      "targetingSignals": [string],
      "processSignals": [string],
      "recoverySuggestions": [string]
    }

    Rules:
    - Each array should contain 1-4 concise, specific bullets.
    - Do not claim a pattern unless at least 3 examples support it.
    - Clearly respect the difference between explicit recruiter feedback and candidate inference.
    - Prefer evidence tied to stage, reason, source, company, role family, and seniority mismatch.
    - Output raw JSON only.
    """

    struct LearningPayload {
        let patternSignals: [String]
        let targetingSignals: [String]
        let processSignals: [String]
        let recoverySuggestions: [String]
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
