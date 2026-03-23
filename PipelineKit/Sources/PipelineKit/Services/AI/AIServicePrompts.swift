import Foundation

public enum AIServicePrompts {
    public static let jobParsingPrompt = """
    You are extracting structured job posting data.

    Return exactly one valid JSON object with this schema and field names:
    {
      "companyName": string,
      "role": string,
      "location": string,
      "jobDescription": string,
      "salaryMin": number|null,
      "salaryMax": number|null,
      "currency": "USD"|"INR"|"EUR"|"GBP"
    }

    Rules:
    - Use empty strings for unknown string fields.
    - Use null for unknown salary fields.
    - Salary numbers must be annual base units as plain integers (example: 120000), not "120k" and no currency symbols.
    - Keep jobDescription concise and useful (maximum 1500 characters).
    - Include remote/hybrid details in location when present.
    - Do not include any fields other than the schema above.
    - Output raw JSON only. No markdown fences. No prose.
    """

    public static func jobParsingUserPrompt(webContent: String) -> String {
        """
        Parse this job posting content:

        \(webContent)
        """
    }

    public static let jobDescriptionDenoisePrompt = """
    You are cleaning an imported job description that may contain browser-extension noise, page chrome, tracking fragments, or unrelated copied text.

    Return exactly one valid JSON object with this schema:
    {
      "cleanedDescription": string
    }

    Rules:
    - Keep only the actual job posting content.
    - Remove extension/browser UI text, duplicate fragments, cookie/login banners, navigation labels, tracking noise, and unrelated footer/header content.
    - Preserve the employer's original meaning, wording, section order, bullet structure, compensation, location, qualifications, and responsibilities whenever they are part of the real posting.
    - Do not summarize, editorialize, or rewrite for style beyond the minimum cleanup needed to remove noise.
    - Keep line breaks and bullets where they help readability.
    - Output raw JSON only. No markdown fences. No prose outside the JSON.
    """

    public static func jobDescriptionDenoiseUserPrompt(description: String) -> String {
        """
        Clean this imported job description and remove unrelated noise while preserving the actual posting:

        \(description)
        """
    }

    public static let atsKeywordExtractionPrompt = """
    You are extracting ATS-relevant resume keywords from a job posting.

    Return exactly one valid JSON object with this schema:
    {
      "keywords": [
        {
          "term": string,
          "aliases": [string],
          "kind": "hard_skill"|"tool"|"platform"|"domain"|"role_concept",
          "importance": "core"|"supporting"
        }
      ]
    }

    Rules:
    - Extract at most 12 keywords.
    - Focus on hard skills, tools, platforms, technical domains, and concrete role concepts that belong on a resume.
    - Favor noun phrases over verbs.
    - Exclude company names, employer self-reference, pronouns, benefits, culture statements, legal boilerplate, and generic filler like "team player" or "they".
    - `aliases` should only include materially useful alternate spellings or abbreviations for matching.
    - Do not include duplicate keywords or aliases.
    - Output raw JSON only. No markdown fences. No prose outside the JSON.
    """

    public static func atsKeywordExtractionUserPrompt(
        companyName: String,
        role: String,
        jobDescription: String
    ) -> String {
        """
        Extract ATS-relevant keywords from this job posting.

        Company:
        \(companyName)

        Role:
        \(role)

        Job Description:
        \(jobDescription)
        """
    }

    public static let jobMatchScoringPrompt = """
    You are evaluating how well a candidate's master resume matches a job description.

    Return exactly one valid JSON object with this schema:
    {
      "skillsScore": number,
      "experienceScore": number,
      "matchedSkills": [string],
      "missingSkills": [string],
      "summary": string,
      "gapAnalysis": string
    }

    Rules:
    - `skillsScore` and `experienceScore` must be integers from 0 to 100.
    - Focus only on evidence present in the provided resume JSON and job description.
    - `matchedSkills` and `missingSkills` should be short skill or requirement phrases.
    - Keep `matchedSkills` and `missingSkills` to at most 8 items each.
    - `summary` should be one or two sentences explaining the fit at a glance.
    - `gapAnalysis` should explain the main missing requirements or concerns in plain language.
    - Do not invent experience or skills not present in the resume.
    - Output raw JSON only. No markdown fences. No prose outside the JSON.
    """

    public static func jobMatchScoringUserPrompt(
        resumeJSON: String,
        jobDescription: String
    ) -> String {
        """
        Compare this candidate resume to the job description and return the required JSON.

        Resume JSON:
        \(resumeJSON)

        Job Description:
        \(jobDescription)
        """
    }
}
