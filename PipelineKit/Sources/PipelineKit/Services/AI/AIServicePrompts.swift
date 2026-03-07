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
}
