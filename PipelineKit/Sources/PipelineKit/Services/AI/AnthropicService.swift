import Foundation

public final class AnthropicService: AIServiceProtocol {
    private let apiKey: String
    private let contentProvider: WebContentProvider
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"

    public init(apiKey: String, contentProvider: WebContentProvider = BasicWebContentProvider(serviceName: "AnthropicService")) {
        self.apiKey = apiKey
        self.contentProvider = contentProvider
    }

    public func parseJobPosting(from url: String, model: String) async throws -> ParsedJobData {
        AIParseDebugLogger.info(
            "AnthropicService: parse start url=\(AIParseDebugLogger.summarizedURL(url)) model=\(model)."
        )

        let webContent = try await contentProvider.fetchText(from: url)
        AIParseDebugLogger.info("AnthropicService: fetched webpage text (\(webContent.count) chars).")

        guard !webContent.isEmpty else {
            AIParseDebugLogger.warning("AnthropicService: webpage content is empty after HTML stripping.")
            throw AIServiceError.parsingError("Fetched page content was empty.")
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 2000,
            "system": AIServicePrompts.jobParsingPrompt,
            "messages": [
                ["role": "user", "content": AIServicePrompts.jobParsingUserPrompt(webContent: webContent)]
            ]
        ]

        guard let requestURL = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let data = try await AIRequestRetry.withRetry {
            try await AIHTTPClient.send(request, serviceName: "AnthropicService")
        }

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
        let usage = json["usage"] as? [String: Any]
        let usageMetrics = AIUsageMetrics(
            promptTokens: intValue(usage?["input_tokens"]),
            completionTokens: intValue(usage?["output_tokens"]),
            totalTokens: nil
        )

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

        AIParseDebugLogger.info("AnthropicService: model output chars=\(text.count).")
        var parsed = try AIResponseParser.parseJobData(from: text)
        parsed.usage = usageMetrics
        return parsed
    }

    private func intValue(_ value: Any?) -> Int? {
        if let intValue = value as? Int {
            return intValue
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let text = value as? String, let intValue = Int(text) {
            return intValue
        }
        return nil
    }
}
