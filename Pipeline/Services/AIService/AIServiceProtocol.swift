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
    Extract job posting information from the following content. Return a JSON object with these fields:
    - companyName: string (the company name)
    - role: string (the job title/position)
    - location: string (job location, include remote if applicable)
    - jobDescription: string (full job description, requirements, and responsibilities)
    - salaryMin: number or null (minimum salary if mentioned, as annual amount)
    - salaryMax: number or null (maximum salary if mentioned, as annual amount)
    - currency: string ("USD", "INR", "EUR", or "GBP" based on salary or location)

    If a field cannot be determined, use reasonable defaults or null for optional fields.
    Return ONLY the JSON object, no additional text.
    """
}

// MARK: - Response Parsing Helper

enum AIResponseParser {
    static func parseJobData(from jsonString: String) throws -> AIParsingViewModel.ParsedJobData {
        let cleaned = stripMarkdownFences(from: jsonString)
        let jsonPayload = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = jsonPayload.data(using: .utf8) else {
            throw AIServiceError.parsingError("Failed to convert response to data")
        }

        let decoder = JSONDecoder()

        struct JobResponse: Decodable {
            let companyName: String?
            let role: String?
            let location: String?
            let jobDescription: String?
            let salaryMin: FlexibleInt?
            let salaryMax: FlexibleInt?
            let currency: String?
        }

        struct FlexibleInt: Decodable {
            let value: Int?

            init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()

                if let intValue = try? container.decode(Int.self) {
                    value = intValue
                    return
                }

                if let doubleValue = try? container.decode(Double.self) {
                    value = Int(doubleValue.rounded())
                    return
                }

                if let stringValue = try? container.decode(String.self) {
                    value = Self.parseInt(from: stringValue)
                    return
                }

                value = nil
            }

            private static func parseInt(from string: String) -> Int? {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }

                let plain = trimmed.replacingOccurrences(of: ",", with: "")
                if let intValue = Int(plain) {
                    return intValue
                }

                if let doubleValue = Double(plain) {
                    return Int(doubleValue.rounded())
                }

                let pattern = #"-?\d+(?:\.\d+)?"#
                guard let regex = try? NSRegularExpression(pattern: pattern),
                      let match = regex.firstMatch(
                        in: plain,
                        range: NSRange(plain.startIndex..., in: plain)
                      ),
                      let range = Range(match.range, in: plain) else {
                    return nil
                }

                let numeric = String(plain[range])
                if let intValue = Int(numeric) {
                    return intValue
                }
                if let doubleValue = Double(numeric) {
                    return Int(doubleValue.rounded())
                }
                return nil
            }
        }

        let response: JobResponse
        do {
            response = try decoder.decode(JobResponse.self, from: data)
        } catch {
            throw AIServiceError.parsingError(error.localizedDescription)
        }

        return AIParsingViewModel.ParsedJobData(
            companyName: response.companyName ?? "",
            role: response.role ?? "",
            location: response.location ?? "",
            jobDescription: response.jobDescription ?? "",
            salaryMin: response.salaryMin?.value,
            salaryMax: response.salaryMax?.value,
            currency: parseCurrency(from: response.currency)
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
