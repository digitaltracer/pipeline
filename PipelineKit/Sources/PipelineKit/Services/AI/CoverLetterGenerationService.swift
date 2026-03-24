import Foundation

public struct CoverLetterGenerationResult: Sendable {
    public let greeting: String
    public let hookParagraph: String
    public let bodyParagraphs: [String]
    public let closingParagraph: String
    public let usage: AIUsageMetrics?

    public init(
        greeting: String,
        hookParagraph: String,
        bodyParagraphs: [String],
        closingParagraph: String,
        usage: AIUsageMetrics? = nil
    ) {
        self.greeting = greeting
        self.hookParagraph = hookParagraph
        self.bodyParagraphs = bodyParagraphs
        self.closingParagraph = closingParagraph
        self.usage = usage
    }

    public var plainText: String {
        CoverLetterDraft.composePlainText(
            greeting: greeting,
            hookParagraph: hookParagraph,
            bodyParagraphs: bodyParagraphs,
            closingParagraph: closingParagraph
        )
    }
}

public struct CoverLetterSectionRegenerationResult: Sendable {
    public let section: CoverLetterSectionKind
    public let paragraphIndex: Int?
    public let text: String
    public let usage: AIUsageMetrics?

    public init(
        section: CoverLetterSectionKind,
        paragraphIndex: Int? = nil,
        text: String,
        usage: AIUsageMetrics? = nil
    ) {
        self.section = section
        self.paragraphIndex = paragraphIndex
        self.text = text
        self.usage = usage
    }
}

public enum CoverLetterGenerationService {
    public static func generateCoverLetter(
        provider: AIProvider,
        apiKey: String,
        model: String,
        tone: CoverLetterTone,
        company: String,
        role: String,
        jobDescription: String,
        notes: String,
        resumeJSON: String
    ) async throws -> CoverLetterGenerationResult {
        let prompts = generationPrompts(
            tone: tone,
            company: company,
            role: role,
            jobDescription: jobDescription,
            notes: notes,
            resumeJSON: resumeJSON
        )

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: prompts.systemPrompt,
            userPrompt: prompts.userPrompt
        )

        return try parseGenerationResponse(response.text, usage: response.usage)
    }

    public static func regenerateSection(
        provider: AIProvider,
        apiKey: String,
        model: String,
        tone: CoverLetterTone,
        section: CoverLetterSectionKind,
        paragraphIndex: Int? = nil,
        currentDraft: CoverLetterGenerationResult,
        company: String,
        role: String,
        jobDescription: String,
        notes: String,
        resumeJSON: String
    ) async throws -> CoverLetterSectionRegenerationResult {
        let prompts = sectionRegenerationPrompts(
            tone: tone,
            section: section,
            paragraphIndex: paragraphIndex,
            currentDraft: currentDraft,
            company: company,
            role: role,
            jobDescription: jobDescription,
            notes: notes,
            resumeJSON: resumeJSON
        )

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: prompts.systemPrompt,
            userPrompt: prompts.userPrompt
        )

        return try parseRegenerationResponse(
            response.text,
            section: section,
            paragraphIndex: paragraphIndex,
            usage: response.usage
        )
    }

    static func generationPrompts(
        tone: CoverLetterTone,
        company: String,
        role: String,
        jobDescription: String,
        notes: String,
        resumeJSON: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let systemPrompt = """
        You are a meticulous career writing assistant who drafts tailored cover letters for job applications.

        Return exactly one valid JSON object with this schema:
        {
          "greeting": string,
          "hookParagraph": string,
          "bodyParagraphs": [string, string],
          "closingParagraph": string
        }

        Rules:
        - Output raw JSON only. No markdown fences. No extra prose.
        - Write in a \(tone.promptDescriptor) tone.
        - The greeting should address the hiring team naturally when no person is provided.
        - The hook paragraph should connect the candidate to the role without repeating the greeting. When the job description or notes mention something specific about the company (mission, product, industry position), reference it. Otherwise, lead with the candidate's strongest relevant qualification.
        - bodyParagraphs must contain 2 or 3 paragraphs. Each body paragraph should follow an evidence-then-impact pattern: name a specific resume experience, then connect it to a specific job requirement.
        - Use only evidence grounded in the provided resume JSON or notes. Do not invent metrics, employers, technologies, or achievements.
        - The closing paragraph should restate fit, invite further discussion, and end with a professional sign-off placeholder such as "Best regards,".
        - Target lengths: hook 40-60 words, each body paragraph 60-100 words, closing 40-60 words, total letter 250-350 words.
        - Avoid cliche openings such as "I am writing to express my interest", "passionate about", "excited to apply", or "I believe I would be a great fit". Start with a confident, specific statement.
        - Do not repeat the exact job title more than once; use natural variations.
        """

        let userPrompt = """
        Draft a tailored cover letter using the context below.

        Company: \(company)
        Role: \(role)
        Tone: \(tone.displayName) (\(tone.promptDescriptor))

        Job Description:
        \(trimmed(jobDescription, maxLength: 7000))

        User Notes:
        \(notes.isEmpty ? "None provided." : trimmed(notes, maxLength: 2500))

        Resume JSON:
        \(trimmed(resumeJSON, maxLength: 12000))
        """

        return (systemPrompt, userPrompt)
    }

    static func sectionRegenerationPrompts(
        tone: CoverLetterTone,
        section: CoverLetterSectionKind,
        paragraphIndex: Int?,
        currentDraft: CoverLetterGenerationResult,
        company: String,
        role: String,
        jobDescription: String,
        notes: String,
        resumeJSON: String
    ) -> (systemPrompt: String, userPrompt: String) {
        let systemPrompt = """
        You are revising one section of a tailored cover letter.

        Return exactly one valid JSON object with this schema:
        {
          "text": string
        }

        Rules:
        - Output raw JSON only. No markdown fences. No extra prose.
        - Rewrite only the requested section.
        - Keep the writing in a \(tone.promptDescriptor) tone.
        - Preserve factual accuracy. Use only information grounded in the resume JSON or notes.
        - Avoid duplicating ideas already covered elsewhere in the letter.
        - If rewriting a body paragraph, keep it focused on role fit and job requirements.
        """

        let sectionDescription: String
        switch section {
        case .greeting:
            sectionDescription = "Greeting"
        case .hook:
            sectionDescription = "Hook paragraph"
        case .bodyParagraph:
            let indexLabel = (paragraphIndex ?? 0) + 1
            sectionDescription = "Body paragraph \(indexLabel)"
        case .closing:
            sectionDescription = "Closing paragraph"
        }

        let userPrompt = """
        Rewrite the requested section of this cover letter.

        Requested Section: \(sectionDescription)
        Company: \(company)
        Role: \(role)
        Tone: \(tone.displayName) (\(tone.promptDescriptor))

        Current Cover Letter:
        Greeting:
        \(currentDraft.greeting)

        Hook Paragraph:
        \(currentDraft.hookParagraph)

        Body Paragraphs:
        \(renderBodyParagraphList(currentDraft.bodyParagraphs))

        Closing Paragraph:
        \(currentDraft.closingParagraph)

        Job Description:
        \(trimmed(jobDescription, maxLength: 7000))

        User Notes:
        \(notes.isEmpty ? "None provided." : trimmed(notes, maxLength: 2500))

        Resume JSON:
        \(trimmed(resumeJSON, maxLength: 12000))
        """

        return (systemPrompt, userPrompt)
    }

    static func parseGenerationResponse(
        _ rawJSON: String,
        usage: AIUsageMetrics? = nil
    ) throws -> CoverLetterGenerationResult {
        let cleaned = stripMarkdownFences(from: rawJSON)
        let candidateJSON = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = candidateJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Cover letter response was not valid JSON.")
        }

        let greeting = trimmed(json["greeting"] as? String ?? "")
        let hookParagraph = trimmed(
            json["hookParagraph"] as? String
                ?? json["hook"] as? String
                ?? ""
        )
        let bodyParagraphs = normalizedParagraphs(from: json["bodyParagraphs"])
        let closingParagraph = trimmed(
            json["closingParagraph"] as? String
                ?? json["closing"] as? String
                ?? ""
        )

        guard !greeting.isEmpty,
              !hookParagraph.isEmpty,
              !bodyParagraphs.isEmpty,
              !closingParagraph.isEmpty else {
            throw AIServiceError.parsingError("Cover letter response was missing required sections.")
        }

        return CoverLetterGenerationResult(
            greeting: greeting,
            hookParagraph: hookParagraph,
            bodyParagraphs: bodyParagraphs,
            closingParagraph: closingParagraph,
            usage: usage
        )
    }

    static func parseRegenerationResponse(
        _ rawJSON: String,
        section: CoverLetterSectionKind,
        paragraphIndex: Int?,
        usage: AIUsageMetrics? = nil
    ) throws -> CoverLetterSectionRegenerationResult {
        let cleaned = stripMarkdownFences(from: rawJSON)
        let candidateJSON = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = candidateJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Cover letter section response was not valid JSON.")
        }

        let text = trimmed(
            json["text"] as? String
                ?? json["paragraph"] as? String
                ?? json["content"] as? String
                ?? ""
        )

        guard !text.isEmpty else {
            throw AIServiceError.parsingError("Cover letter section response was empty.")
        }

        return CoverLetterSectionRegenerationResult(
            section: section,
            paragraphIndex: paragraphIndex,
            text: text,
            usage: usage
        )
    }

    private static func normalizedParagraphs(from value: Any?) -> [String] {
        if let array = value as? [String] {
            return array
                .map { trimmed($0) }
                .filter { !$0.isEmpty }
        }

        if let array = value as? [Any] {
            return array.compactMap { item in
                guard let text = item as? String else { return nil }
                return trimmed(text)
            }
            .filter { !$0.isEmpty }
        }

        if let string = value as? String {
            return string
                .components(separatedBy: "\n\n")
                .map { trimmed($0) }
                .filter { !$0.isEmpty }
        }

        return []
    }

    private static func renderBodyParagraphList(_ paragraphs: [String]) -> String {
        guard !paragraphs.isEmpty else { return "None." }

        return paragraphs.enumerated()
            .map { index, paragraph in
                "\(index + 1). \(paragraph)"
            }
            .joined(separator: "\n")
    }

    private static func trimmed(_ value: String, maxLength: Int? = nil) -> String {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let maxLength, trimmedValue.count > maxLength else {
            return trimmedValue
        }
        return String(trimmedValue.prefix(maxLength))
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
