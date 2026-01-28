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
        // Clean up the response - remove markdown code blocks if present
        var cleaned = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        }
        if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8) else {
            throw AIServiceError.parsingError("Failed to convert response to data")
        }

        let decoder = JSONDecoder()

        struct JobResponse: Codable {
            let companyName: String?
            let role: String?
            let location: String?
            let jobDescription: String?
            let salaryMin: Int?
            let salaryMax: Int?
            let currency: String?
        }

        let response = try decoder.decode(JobResponse.self, from: data)

        let currencyEnum: Currency
        switch response.currency?.uppercased() {
        case "USD": currencyEnum = .usd
        case "INR": currencyEnum = .inr
        case "EUR": currencyEnum = .eur
        case "GBP": currencyEnum = .gbp
        default: currencyEnum = .usd
        }

        return AIParsingViewModel.ParsedJobData(
            companyName: response.companyName ?? "",
            role: response.role ?? "",
            location: response.location ?? "",
            jobDescription: response.jobDescription ?? "",
            salaryMin: response.salaryMin,
            salaryMax: response.salaryMax,
            currency: currencyEnum
        )
    }
}
