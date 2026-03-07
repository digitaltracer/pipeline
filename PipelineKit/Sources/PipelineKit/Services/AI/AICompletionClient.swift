import Foundation

public struct AIUsageMetrics: Codable, Sendable, Equatable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?

    public init(promptTokens: Int? = nil, completionTokens: Int? = nil, totalTokens: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
    }
}

public struct AICompletionResponse: Sendable, Equatable {
    public let text: String
    public let usage: AIUsageMetrics?

    public init(text: String, usage: AIUsageMetrics? = nil) {
        self.text = text
        self.usage = usage
    }
}

/// A lightweight client that sends a system + user prompt to any supported AI provider
/// and returns the raw text response. Reusable across Interview Prep, Follow-up Drafter, etc.
public enum AICompletionClient {

    public static func complete(
        provider: AIProvider,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4000,
        temperature: Double = 0.3
    ) async throws -> String {
        try await completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: maxTokens,
            temperature: temperature
        ).text
    }

    public static func completeWithUsage(
        provider: AIProvider,
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int = 4000,
        temperature: Double = 0.3
    ) async throws -> AICompletionResponse {
        switch provider {
        case .openAI:
            return try await completeOpenAI(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        case .anthropic:
            return try await completeAnthropic(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        case .gemini:
            return try await completeGemini(
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: maxTokens,
                temperature: temperature
            )
        }
    }

    // MARK: - OpenAI

    private static func completeOpenAI(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AICompletionResponse {
        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt]
            ],
            "temperature": temperature,
            "max_tokens": maxTokens
        ]

        let data = try await sendRequest(
            url: "https://api.openai.com/v1/chat/completions",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: requestBody,
            providerName: "OpenAI"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let finishReason = (firstChoice["finish_reason"] as? String) ?? "unknown"
        let usage = json["usage"] as? [String: Any]
        let usageMetrics = makeUsage(
            prompt: intValue(usage?["prompt_tokens"]),
            completion: intValue(usage?["completion_tokens"]),
            total: intValue(usage?["total_tokens"])
        )

        AIParseDebugLogger.info(
            "AICompletionClient(OpenAI): model=\(model) finish_reason=\(finishReason) prompt_tokens=\(tokenString(usage?["prompt_tokens"])) completion_tokens=\(tokenString(usage?["completion_tokens"])) total_tokens=\(tokenString(usage?["total_tokens"]))."
        )

        if let text = message["content"] as? String, !text.isEmpty {
            return AICompletionResponse(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                usage: usageMetrics
            )
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts
                .compactMap { ($0["text"] as? String) ?? ($0["content"] as? String) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                return AICompletionResponse(text: text, usage: usageMetrics)
            }
        }

        throw AIServiceError.invalidResponse
    }

    // MARK: - Anthropic

    private static func completeAnthropic(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AICompletionResponse {
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        let data = try await sendRequest(
            url: "https://api.anthropic.com/v1/messages",
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "Content-Type": "application/json"
            ],
            body: requestBody,
            providerName: "Anthropic"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentBlocks = json["content"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let stopReason = (json["stop_reason"] as? String) ?? "unknown"
        let stopSequence = json["stop_sequence"] as? String
        let usage = json["usage"] as? [String: Any]
        let usageMetrics = makeUsage(
            prompt: intValue(usage?["input_tokens"]),
            completion: intValue(usage?["output_tokens"]),
            total: nil
        )

        AIParseDebugLogger.info(
            "AICompletionClient(Anthropic): model=\(model) stop_reason=\(stopReason) stop_sequence=\(stopSequence ?? "<nil>") input_tokens=\(tokenString(usage?["input_tokens"])) output_tokens=\(tokenString(usage?["output_tokens"]))."
        )

        let text = contentBlocks
            .compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw AIServiceError.invalidResponse }
        return AICompletionResponse(text: text, usage: usageMetrics)
    }

    // MARK: - Gemini

    private static func completeGemini(
        apiKey: String,
        model: String,
        systemPrompt: String,
        userPrompt: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> AICompletionResponse {
        let prompt = "\(systemPrompt)\n\n\(userPrompt)"

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "temperature": temperature,
                "maxOutputTokens": maxTokens
            ]
        ]

        let data = try await sendRequest(
            url: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent",
            headers: [
                "Content-Type": "application/json",
                "x-goog-api-key": apiKey
            ],
            body: requestBody,
            providerName: "Gemini"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              !candidates.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        let usage = json["usageMetadata"] as? [String: Any]
        let usageMetrics = makeUsage(
            prompt: intValue(usage?["promptTokenCount"]),
            completion: intValue(usage?["candidatesTokenCount"]),
            total: intValue(usage?["totalTokenCount"])
        )

        let finishReasons = candidates
            .compactMap { $0["finishReason"] as? String }
            .joined(separator: ",")

        AIParseDebugLogger.info(
            "AICompletionClient(Gemini): model=\(model) finish_reasons=[\(finishReasons)] prompt_tokens=\(tokenString(usage?["promptTokenCount"])) completion_tokens=\(tokenString(usage?["candidatesTokenCount"])) total_tokens=\(tokenString(usage?["totalTokenCount"]))."
        )

        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }

            let text = parts
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty {
                let finishReason = (candidate["finishReason"] as? String) ?? "unknown"
                AIParseDebugLogger.info(
                    "AICompletionClient(Gemini): selected candidate finish_reason=\(finishReason) output_chars=\(text.count)."
                )
                return AICompletionResponse(text: text, usage: usageMetrics)
            }
        }

        throw AIServiceError.invalidResponse
    }

    // MARK: - Shared HTTP

    private static func sendRequest(
        url: String,
        headers: [String: String],
        body: [String: Any],
        providerName: String
    ) async throws -> Data {
        guard let requestURL = URL(string: url) else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info(
            "AICompletionClient(\(providerName)): HTTP \(httpResponse.statusCode), bytes=\(data.count)."
        )

        switch httpResponse.statusCode {
        case 200:
            return data
        case 401, 403:
            throw AIServiceError.unauthorized
        case 429:
            throw AIServiceError.rateLimited
        default:
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                AIParseDebugLogger.error(
                    "AICompletionClient(\(providerName)): API error status=\(httpResponse.statusCode) message=\(message)."
                )
                throw AIServiceError.apiError(message)
            }
            AIParseDebugLogger.error(
                "AICompletionClient(\(providerName)): API error status=\(httpResponse.statusCode) response body redacted bytes=\(data.count)."
            )
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }

    private static func intValue(_ value: Any?) -> Int? {
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

    private static func makeUsage(prompt: Int?, completion: Int?, total: Int?) -> AIUsageMetrics? {
        let resolvedTotal = total ?? {
            guard let prompt, let completion else { return nil }
            return prompt + completion
        }()

        guard prompt != nil || completion != nil || resolvedTotal != nil else {
            return nil
        }

        return AIUsageMetrics(
            promptTokens: prompt,
            completionTokens: completion,
            totalTokens: resolvedTotal
        )
    }

    private static func tokenString(_ value: Any?) -> String {
        guard let value else { return "n/a" }
        if let intValue = value as? Int {
            return String(intValue)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let text = value as? String, !text.isEmpty {
            return text
        }
        return "n/a"
    }
}
