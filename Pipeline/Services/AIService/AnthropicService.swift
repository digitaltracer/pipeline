import Foundation

final class AnthropicService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData {
        AIParseDebugLogger.info(
            "AnthropicService: parse start url=\(AIParseDebugLogger.summarizedURL(url)) model=\(model)."
        )

        // First, fetch the webpage content
        let webContent = try await fetchWebContent(from: url)
        AIParseDebugLogger.info("AnthropicService: fetched webpage text (\(webContent.count) chars).")

        guard !webContent.isEmpty else {
            AIParseDebugLogger.warning("AnthropicService: webpage content is empty after HTML stripping.")
            throw AIServiceError.parsingError("Fetched page content was empty.")
        }

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

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AIParseDebugLogger.error(
                "AnthropicService: network error during Anthropic call: \(error.localizedDescription)."
            )
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AIParseDebugLogger.error("AnthropicService: missing HTTP response from Anthropic.")
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info(
            "AnthropicService: Anthropic response status=\(httpResponse.statusCode) bytes=\(data.count)."
        )

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
                AIParseDebugLogger.error(
                    "AnthropicService: API error status=\(httpResponse.statusCode) message=\(message)."
                )
                throw AIServiceError.apiError(message)
            }
            AIParseDebugLogger.error("AnthropicService: API error status=\(httpResponse.statusCode).")
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }

        // Parse the response
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIServiceError.parsingError("Unable to decode Anthropic response.")
        }

        guard let json = jsonObject as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            AIParseDebugLogger.error("AnthropicService: response JSON missing expected fields.")
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
            AIParseDebugLogger.error("AnthropicService: model content text is empty.")
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info(
            "AnthropicService: model output preview: \(AIParseDebugLogger.preview(text, maxLength: 280))."
        )
        return try AIResponseParser.parseJobData(from: text)
    }

    private func fetchWebContent(from urlString: String) async throws -> String {
        try await WebContentFetcher.fetchText(from: urlString, serviceName: "AnthropicService")
    }
}
