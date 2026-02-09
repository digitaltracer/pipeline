import Foundation

// MARK: - Protocol

protocol AIServiceProtocol {
    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case invalidResponse
    case apiError(String)
    case rateLimited
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .unauthorized:
            return "Invalid API key. Please check your settings."
        }
    }
}

// MARK: - Common Prompt

enum AIServicePrompts {
    static let jobParsingPrompt = """
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
    - Include remote/hybrid details in location when present.
    - Do not include any fields other than the schema above.
    - Output raw JSON only. No markdown fences. No prose.
    """

    static func jobParsingUserPrompt(webContent: String) -> String {
        """
        Parse this job posting content:

        \(webContent)
        """
    }
}

// MARK: - Response Parsing Helper

enum AIResponseParser {
    static func parseJobData(from jsonString: String) throws -> AIParsingViewModel.ParsedJobData {
        let cleaned = stripMarkdownFences(from: jsonString)
        let jsonPayload = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = jsonPayload.data(using: .utf8) else {
            throw AIServiceError.parsingError("Failed to convert response to data")
        }

        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Response was not a JSON object")
        }

        let companyName = parseString(
            in: root,
            keys: ["companyName", "company", "company_name", "employer", "organization"]
        )
        let role = parseString(
            in: root,
            keys: ["role", "jobTitle", "job_title", "title", "position"]
        )
        let location = parseString(
            in: root,
            keys: ["location", "jobLocation", "job_location", "city", "place"]
        )
        let jobDescription = parseString(
            in: root,
            keys: ["jobDescription", "job_description", "description", "summary"]
        )
        let salaryMin = parseInt(
            in: root,
            keys: ["salaryMin", "salary_min", "minSalary", "min_salary", "salaryFrom", "salary_from"]
        )
        let salaryMax = parseInt(
            in: root,
            keys: ["salaryMax", "salary_max", "maxSalary", "max_salary", "salaryTo", "salary_to"]
        )
        let currency = parseString(
            in: root,
            keys: ["currency", "salaryCurrency", "salary_currency"]
        )

        return AIParsingViewModel.ParsedJobData(
            companyName: companyName,
            role: role,
            location: location,
            jobDescription: jobDescription,
            salaryMin: salaryMin,
            salaryMax: salaryMax,
            currency: parseCurrency(from: currency)
        )
    }

    private static func parseCurrency(from rawValue: String?) -> Currency {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""

        if normalized.contains("INR") || normalized.contains("RUPEE") || normalized.contains("₹") {
            return .inr
        }
        if normalized.contains("EUR") || normalized.contains("EURO") || normalized.contains("€") {
            return .eur
        }
        if normalized.contains("GBP") || normalized.contains("POUND") || normalized.contains("£") {
            return .gbp
        }
        if normalized.contains("USD") || normalized.contains("DOLLAR") || normalized.contains("$") {
            return .usd
        }

        return .usd
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

    private static func parseString(in root: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = root[key] else { continue }

            if value is NSNull {
                continue
            }

            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        return ""
    }

    private static func parseInt(in root: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = root[key] else { continue }
            if let parsed = parseIntValue(value) {
                return parsed
            }
        }

        return nil
    }

    private static func parseIntValue(_ value: Any) -> Int? {
        if value is NSNull {
            return nil
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let doubleValue = value as? Double {
            return Int(doubleValue.rounded())
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let stringValue = value as? String {
            return parseInt(from: stringValue)
        }

        return nil
    }

    private static func parseInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")

        if let intValue = Int(sanitized) {
            return intValue
        }

        if let doubleValue = Double(sanitized) {
            return Int(doubleValue.rounded())
        }

        let compact = sanitized.replacingOccurrences(of: " ", with: "")
        if let suffixed = parseWithSuffix(compact) {
            return suffixed
        }

        let pattern = #"-?\d+(?:\.\d+)?(?:[kmb])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: compact,
                range: NSRange(compact.startIndex..., in: compact)
              ),
              let range = Range(match.range, in: compact) else {
            return nil
        }

        return parseWithSuffix(String(compact[range]))
    }

    private static func parseWithSuffix(_ token: String) -> Int? {
        guard !token.isEmpty else { return nil }

        let lower = token.lowercased()
        let last = lower.last
        let multiplier: Double
        let numberPortion: String

        switch last {
        case "k":
            multiplier = 1_000
            numberPortion = String(lower.dropLast())
        case "m":
            multiplier = 1_000_000
            numberPortion = String(lower.dropLast())
        case "b":
            multiplier = 1_000_000_000
            numberPortion = String(lower.dropLast())
        default:
            multiplier = 1
            numberPortion = lower
        }

        if let intValue = Int(numberPortion), multiplier == 1 {
            return intValue
        }

        guard let numeric = Double(numberPortion) else {
            return nil
        }

        return Int((numeric * multiplier).rounded())
    }

    /// Extract the first balanced JSON object from mixed text output.
    private static func extractJSONObject(from text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
        }

        return nil
    }
}
