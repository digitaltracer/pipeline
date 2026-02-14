import Foundation

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
        switch provider {
        case .openAI:
            return try await completeOpenAI(
                apiKey: apiKey, model: model,
                systemPrompt: systemPrompt, userPrompt: userPrompt,
                maxTokens: maxTokens, temperature: temperature
            )
        case .anthropic:
            return try await completeAnthropic(
                apiKey: apiKey, model: model,
                systemPrompt: systemPrompt, userPrompt: userPrompt,
                maxTokens: maxTokens, temperature: temperature
            )
        case .gemini:
            return try await completeGemini(
                apiKey: apiKey, model: model,
                systemPrompt: systemPrompt, userPrompt: userPrompt,
                maxTokens: maxTokens, temperature: temperature
            )
        }
    }

    // MARK: - OpenAI

    private static func completeOpenAI(
        apiKey: String, model: String,
        systemPrompt: String, userPrompt: String,
        maxTokens: Int, temperature: Double
    ) async throws -> String {
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

        if let text = message["content"] as? String, !text.isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let parts = message["content"] as? [[String: Any]] {
            let text = parts
                .compactMap { ($0["text"] as? String) ?? ($0["content"] as? String) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return text }
        }

        throw AIServiceError.invalidResponse
    }

    // MARK: - Anthropic

    private static func completeAnthropic(
        apiKey: String, model: String,
        systemPrompt: String, userPrompt: String,
        maxTokens: Int, temperature: Double
    ) async throws -> String {
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

        let text = contentBlocks
            .compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !text.isEmpty else { throw AIServiceError.invalidResponse }
        return text
    }

    // MARK: - Gemini

    private static func completeGemini(
        apiKey: String, model: String,
        systemPrompt: String, userPrompt: String,
        maxTokens: Int, temperature: Double
    ) async throws -> String {
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

        for candidate in candidates {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { continue }

            let text = parts
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !text.isEmpty { return text }
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
                throw AIServiceError.apiError(message)
            }
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
}
