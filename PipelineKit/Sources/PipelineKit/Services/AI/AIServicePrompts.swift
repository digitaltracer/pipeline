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
}
