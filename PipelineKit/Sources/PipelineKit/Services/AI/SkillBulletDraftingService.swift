import Foundation

public struct SkillBulletDraft: Sendable {
    public let bulletText: String
    public let usage: AIUsageMetrics?
}

public enum SkillBulletDraftingService {

    public static func draft(
        provider: AIProvider,
        apiKey: String,
        model: String,
        skillName: String,
        jobTitle: String,
        company: String,
        existingResponsibilities: [String],
        jobDescription: String? = nil
    ) async throws -> SkillBulletDraft {
        let systemPrompt = ResumeTailoringPrompts.skillBulletDraftSystemPrompt

        let userPrompt = ResumeTailoringPrompts.skillBulletDraftUserPrompt(
            skillName: skillName,
            jobTitle: jobTitle,
            company: company,
            existingResponsibilities: existingResponsibilities,
            jobDescription: jobDescription
        )

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: 1024,
            temperature: 0.4
        )

        let cleaned = cleanBulletText(response.text)

        guard !cleaned.isEmpty else {
            throw AIServiceError.parsingError("AI returned an empty bullet.")
        }

        return SkillBulletDraft(bulletText: cleaned, usage: response.usage)
    }

    private static func cleanBulletText(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip leading list markers (- , * , • )
        if let first = text.first, first == "-" || first == "*" || first == "•" {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        // Strip surrounding quotes
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }

        // Strip trailing period if present (resume bullets often omit it)
        if text.hasSuffix(".") {
            text = String(text.dropLast())
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
