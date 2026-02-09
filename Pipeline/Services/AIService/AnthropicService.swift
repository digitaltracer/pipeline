import Foundation

final class AnthropicService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData {
        // First, fetch the webpage content
        let webContent = try await fetchWebContent(from: url)

        // Build the request
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": AIServicePrompts.jobParsingPrompt,
            "messages": [
                ["role": "user", "content": AIServicePrompts.jobParsingUserPrompt(webContent: webContent)]
            ]
        ]

        guard let url = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
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
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let text = contentBlocks
            .compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        return try AIResponseParser.parseJobData(from: text)
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

        return stripHTML(html)
    }

    private func stripHTML(_ html: String) -> String {
        var text = html

        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)

        if text.count > 15000 {
            text = String(text.prefix(15000))
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
