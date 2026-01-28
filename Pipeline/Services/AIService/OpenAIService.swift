import Foundation

final class OpenAIService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData {
        // First, fetch the webpage content
        let webContent = try await fetchWebContent(from: url)

        // Build the request
        let messages: [[String: Any]] = [
            ["role": "system", "content": AIServicePrompts.jobParsingPrompt],
            ["role": "user", "content": "Parse this job posting:\n\n\(webContent)"]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 2000
        ]

        guard let url = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401:
            throw AIServiceError.unauthorized
        case 429:
            throw AIServiceError.rateLimited
        default:
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw AIServiceError.apiError(message)
            }
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse the response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }

        return try AIResponseParser.parseJobData(from: content)
    }

    private func fetchWebContent(from urlString: String) async throws -> String {
        guard let url = URL(string: urlString) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", forHTTPHeaderField: "User-Agent")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let html = String(data: data, encoding: .utf8) else {
            throw AIServiceError.parsingError("Failed to decode webpage")
        }

        // Basic HTML to text conversion
        return stripHTML(html)
    }

    private func stripHTML(_ html: String) -> String {
        var text = html

        // Remove script and style tags with their content
        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)

        // Remove HTML tags
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        // Clean up whitespace
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        // Limit length to avoid token limits
        if text.count > 15000 {
            text = String(text.prefix(15000))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
