import Foundation

public enum ResumeTailoringPrompts {
    public static let systemPrompt = """
    You are a precise resume tailoring assistant.

    You must return exactly one JSON object with this schema:
    {
      "patches": [
        {
          "id": "UUID string",
          "path": "JSON pointer path",
          "operation": "add" | "replace" | "remove",
          "beforeValue": any JSON value or null,
          "afterValue": any JSON value or null,
          "reason": "short explanation",
          "evidencePaths": ["JSON pointer paths from existing resume"],
          "risk": "low" | "medium" | "high"
        }
      ],
      "sectionGaps": ["short bullet strings"]
    }

    Rules:
    - Do not add unrelated skills or technologies.
    - Any skills change MUST be explicitly evidence-backed by evidencePaths from experience, projects, or summary.
    - Prefer rewriting and reordering over adding new content.
    - You may propose removals only when clearly irrelevant to the target role.
    - Keep all patches grounded in the existing resume; do not invent experience.
    - Keep all new/edited text concise and resume-ready.
    - Summary must be at most 80 words.
    - Each responsibility/project bullet must be at most 32 words.
    - Do not produce long paragraphs; prefer compact phrasing.
    - Use valid JSON pointer paths.
    - Output raw JSON only. No markdown, no prose.
    """

    public static let compactRetrySystemPrompt = """
    You are a precise resume tailoring assistant.

    Return exactly one JSON object with this schema:
    {
      "patches": [
        {
          "id": "UUID string",
          "path": "JSON pointer path",
          "operation": "add" | "replace" | "remove",
          "beforeValue": any JSON value or null,
          "afterValue": any JSON value or null,
          "reason": "short explanation",
          "evidencePaths": ["JSON pointer paths from existing resume"],
          "risk": "low" | "medium" | "high"
        }
      ],
      "sectionGaps": ["short bullet strings"]
    }

    Hard limits:
    - Keep total response under 1800 characters.
    - Return minified JSON on a single line.
    - Maximum 6 patches.
    - Keep each reason under 12 words.
    - Summary must be at most 80 words.
    - Each responsibility/project bullet must be at most 32 words.
    - Do not copy long original text into beforeValue. Use null if original value is long (>120 chars).
    - Keep sectionGaps to at most 5 short items.
    - Output raw JSON only. No markdown, no prose.
    """

    public static let patchRevisionSystemPrompt = """
    You are a precise resume tailoring assistant.

    You must return exactly one JSON object with this schema:
    {
      "patches": [
        {
          "id": "UUID string",
          "path": "JSON pointer path",
          "operation": "add" | "replace" | "remove",
          "beforeValue": any JSON value or null,
          "afterValue": any JSON value or null,
          "reason": "short explanation",
          "evidencePaths": ["JSON pointer paths from existing resume"],
          "risk": "low" | "medium" | "high"
        }
      ],
      "sectionGaps": []
    }

    Rules:
    - Return exactly one patch.
    - Modify only the selected JSON pointer path provided in the user prompt.
    - Keep the patch grounded in existing resume evidence.
    - Keep all edited text concise and resume-ready.
    - Summary must be at most 80 words.
    - Each responsibility/project bullet must be at most 32 words.
    - Do not output markdown or prose.
    """

    public static let patchRevisionCompactRetrySystemPrompt = """
    You are a precise resume tailoring assistant.

    Return exactly one JSON object with this schema:
    {
      "patches": [
        {
          "id": "UUID string",
          "path": "JSON pointer path",
          "operation": "add" | "replace" | "remove",
          "beforeValue": any JSON value or null,
          "afterValue": any JSON value or null,
          "reason": "short explanation",
          "evidencePaths": ["JSON pointer paths from existing resume"],
          "risk": "low" | "medium" | "high"
        }
      ],
      "sectionGaps": []
    }

    Hard limits:
    - Keep total response under 900 characters.
    - Return minified JSON on a single line.
    - Return exactly one patch for the selected path.
    - Keep reason under 10 words.
    - Output raw JSON only. No markdown, no prose.
    """

    public static func userPrompt(
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        additionalInstructions: String? = nil
    ) -> String {
        var prompt = """
        Tailor the resume to this job.

        Company: \(company)
        Role: \(role)

        Job Description:
        \(jobDescription)

        Resume JSON:
        \(resumeJSON)
        """

        if let additionalInstructions,
           !additionalInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\nAdditional tailoring instructions:\n\(additionalInstructions)"
        }

        return prompt
    }

    public static func atsFixInstructions(
        summary: String,
        missingKeywords: [String],
        criticalFindings: [String],
        warningFindings: [String]
    ) -> String {
        var lines: [String] = [
            "This run is specifically for ATS compatibility fixes."
        ]

        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("ATS summary: \(summary)")
        }

        if !missingKeywords.isEmpty {
            lines.append("Prioritize these missing keywords when the resume already provides supporting evidence: \(missingKeywords.joined(separator: ", ")).")
        }

        if !criticalFindings.isEmpty {
            lines.append("Address these critical ATS findings: \(criticalFindings.joined(separator: " | ")).")
        }

        if !warningFindings.isEmpty {
            lines.append("Address these warning ATS findings: \(warningFindings.joined(separator: " | ")).")
        }

        lines.append("Favor patches that improve ATS keyword coverage, section clarity, and parseability without inventing experience.")
        return lines.joined(separator: "\n")
    }

    public static func patchRevisionUserPrompt(
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        selectedPatch: ResumePatch,
        userInstruction: String
    ) -> String {
        """
        Revise one suggested patch using user feedback.

        Company: \(company)
        Role: \(role)
        Selected patch path: \(selectedPatch.path)

        User feedback:
        \(userInstruction)

        Existing suggested patch:
        \(encodedPatch(selectedPatch))

        Job Description:
        \(jobDescription)

        Resume JSON:
        \(resumeJSON)
        """
    }

    private static func encodedPatch(_ patch: ResumePatch) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(patch),
              let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }
}
