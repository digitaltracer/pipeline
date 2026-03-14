import Foundation

public struct ReferralRequestDraftResult: Sendable {
    public let subject: String
    public let body: String
    public let usage: AIUsageMetrics?

    public init(subject: String, body: String, usage: AIUsageMetrics? = nil) {
        self.subject = subject
        self.body = body
        self.usage = usage
    }
}

public enum ReferralRequestDrafterService {
    public static func generateDraft(
        provider: AIProvider,
        apiKey: String,
        model: String,
        company: String,
        role: String,
        contactName: String,
        contactCompany: String?,
        relationship: String?,
        resumeJSON: String?,
        notes: String
    ) async throws -> ReferralRequestDraftResult {
        let systemPrompt = """
        You draft warm, concise, professional referral request emails for job seekers.

        Return exactly one valid JSON object with this schema:
        {
          "subject": string,
          "body": string
        }

        Rules:
        - Write a personalized referral request email.
        - Mention the contact by name naturally.
        - Reference the role and company naturally.
        - Keep the tone warm, concise, and professional.
        - Keep the email body between 120 and 220 words.
        - Start with a greeting and end with a professional sign-off.
        - Never invent a prior relationship that is not in the prompt.
        - Output raw JSON only.
        """

        var userPrompt = """
        Contact Name: \(contactName)
        Contact Company: \(contactCompany ?? company)
        Target Company: \(company)
        Target Role: \(role)
        """

        if let relationship = CompanyProfile.normalizedText(relationship) {
            userPrompt += "\nRelationship Context: \(relationship)"
        }

        if !notes.isEmpty {
            userPrompt += "\n\nApplication Context:\n\(notes)"
        }

        if let resumeJSON = CompanyProfile.normalizedText(resumeJSON) {
            userPrompt += "\n\nCurrent Resume JSON:\n\(String(resumeJSON.prefix(5000)))"
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt
        )

        return try parseResponse(response.text, usage: response.usage)
    }

    private static func parseResponse(_ rawJSON: String, usage: AIUsageMetrics?) throws -> ReferralRequestDraftResult {
        let cleaned = rawJSON
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^```[a-zA-Z0-9_-]*\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["subject"] as? String,
              let body = json["body"] as? String else {
            throw AIServiceError.parsingError("Referral request response was not valid JSON.")
        }

        return ReferralRequestDraftResult(subject: subject, body: body, usage: usage)
    }
}
