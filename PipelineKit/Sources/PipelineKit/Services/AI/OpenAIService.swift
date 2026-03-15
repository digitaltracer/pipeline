import Foundation

public final class OpenAIService: AIServiceProtocol {
    private let apiKey: String
    private let contentProvider: WebContentProvider
    private let baseURL = "https://api.openai.com/v1/chat/completions"

    public init(apiKey: String, contentProvider: WebContentProvider = BasicWebContentProvider(serviceName: "OpenAIService")) {
        self.apiKey = apiKey
        self.contentProvider = contentProvider
    }

    public func parseJobPosting(from url: String, model: String) async throws -> ParsedJobData {
        AIParseDebugLogger.info(
            "OpenAIService: parse start url=\(AIParseDebugLogger.summarizedURL(url)) model=\(model)."
        )

        let webContent = try await contentProvider.fetchText(from: url)
        AIParseDebugLogger.info("OpenAIService: fetched webpage text (\(webContent.count) chars).")

        guard !webContent.isEmpty else {
            AIParseDebugLogger.warning("OpenAIService: webpage content is empty after HTML stripping.")
            throw AIServiceError.parsingError("Fetched page content was empty.")
        }

        let messages: [[String: Any]] = [
            ["role": "system", "content": AIServicePrompts.jobParsingPrompt],
            ["role": "user", "content": AIServicePrompts.jobParsingUserPrompt(webContent: webContent)]
        ]

        let requestBody: [String: Any] = [
            "model": model,
            "messages": messages,
            "temperature": 0.1,
            "max_tokens": 2000
        ]

        guard let requestURL = URL(string: baseURL) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let data = try await AIRequestRetry.withRetry {
            try await AIHTTPClient.send(request, serviceName: "OpenAIService")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIServiceError.parsingError("Unable to decode OpenAI response.")
        }

        guard let json = jsonObject as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            AIParseDebugLogger.error("OpenAIService: response JSON missing expected fields.")
            throw AIServiceError.invalidResponse
        }
        let usage = json["usage"] as? [String: Any]
        let usageMetrics = AIUsageMetrics(
            promptTokens: intValue(usage?["prompt_tokens"]),
            completionTokens: intValue(usage?["completion_tokens"]),
            totalTokens: intValue(usage?["total_tokens"])
        )

        let contentText: String
        if let text = message["content"] as? String {
            contentText = text
        } else if let parts = message["content"] as? [[String: Any]] {
            contentText = parts
                .compactMap { part -> String? in
                    if let text = part["text"] as? String {
                        return text
                    }
                    if let nested = part["content"] as? String {
                        return nested
                    }
                    return nil
                }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            contentText = ""
        }

        guard !contentText.isEmpty else {
            AIParseDebugLogger.error("OpenAIService: model content text is empty.")
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info("OpenAIService: model output chars=\(contentText.count).")
        var parsed = try AIResponseParser.parseJobData(from: contentText)
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
