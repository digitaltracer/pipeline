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

public struct AIWebSearchCitation: Codable, Sendable, Equatable {
    public let title: String
    public let urlString: String
    public let snippet: String?
    public let sourceDomain: String?
    public let rawPayload: String?

    public init(
        title: String,
        urlString: String,
        snippet: String? = nil,
        sourceDomain: String? = nil,
        rawPayload: String? = nil
    ) {
        self.title = title
        self.urlString = urlString
        self.snippet = snippet
        self.sourceDomain = sourceDomain
        self.rawPayload = rawPayload
    }
}

public struct AIWebSearchResponse: Sendable, Equatable {
    public let text: String
    public let citations: [AIWebSearchCitation]
    public let usage: AIUsageMetrics?

    public init(text: String, citations: [AIWebSearchCitation], usage: AIUsageMetrics? = nil) {
        self.text = text
        self.citations = citations
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

    public static func supportsWebSearch(
        provider: AIProvider,
        model: String
    ) -> Bool {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedModel.isEmpty else { return false }

        switch provider {
        case .openAI:
            return normalizedModel.hasPrefix("gpt-") || normalizedModel.hasPrefix("o")
        case .anthropic:
            return normalizedModel.contains("claude")
        case .gemini:
            return normalizedModel.contains("gemini")
        }
    }

    public static func groundedWebSearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String? = nil,
        domains: [String] = [],
        maxTokens: Int = 900
    ) async throws -> AIWebSearchResponse {
        switch provider {
        case .openAI:
            return try await groundedWebSearchOpenAI(
                apiKey: apiKey,
                model: model,
                query: query,
                systemPrompt: systemPrompt,
                domains: domains,
                maxTokens: maxTokens
            )
        case .anthropic:
            return try await groundedWebSearchAnthropic(
                apiKey: apiKey,
                model: model,
                query: query,
                systemPrompt: systemPrompt,
                domains: domains,
                maxTokens: maxTokens
            )
        case .gemini:
            return try await groundedWebSearchGemini(
                apiKey: apiKey,
                model: model,
                query: query,
                systemPrompt: systemPrompt,
                domains: domains,
                maxTokens: maxTokens
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

    private static func groundedWebSearchOpenAI(
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse {
        var requestBody: [String: Any] = [
            "model": model,
            "input": makeWebSearchInput(query: query, systemPrompt: systemPrompt),
            "tools": [[
                "type": "web_search"
            ]],
            "max_output_tokens": maxTokens
        ]

        if !domains.isEmpty {
            requestBody["tool_choice"] = [
                "type": "web_search"
            ]
        }

        let data = try await sendRequest(
            url: "https://api.openai.com/v1/responses",
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: requestBody,
            providerName: "OpenAI Web Search"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let usageMetrics = makeUsage(
            prompt: intValue(usage?["input_tokens"]),
            completion: intValue(usage?["output_tokens"]),
            total: intValue(usage?["total_tokens"])
        )

        let text = extractOpenAIResponseText(json).trimmingCharacters(in: .whitespacesAndNewlines)
        let citations = extractOpenAICitations(json)
            .filter { citation in
                domains.isEmpty || domains.contains(where: {
                    citation.urlString.localizedCaseInsensitiveContains($0)
                })
            }

        guard !text.isEmpty || !citations.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        return AIWebSearchResponse(
            text: text,
            citations: citations,
            usage: usageMetrics
        )
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

    private static func groundedWebSearchAnthropic(
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse {
        var tool: [String: Any] = [
            "type": "web_search_20250305",
            "name": "web_search"
        ]
        if !domains.isEmpty {
            tool["allowed_domains"] = domains
        }

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": systemPrompt ?? "Search the web and return source-backed findings.",
            "messages": [
                ["role": "user", "content": query]
            ],
            "tools": [tool]
        ]

        let data = try await sendRequest(
            url: "https://api.anthropic.com/v1/messages",
            headers: [
                "x-api-key": apiKey,
                "anthropic-version": "2023-06-01",
                "anthropic-beta": "web-search-2025-03-05",
                "Content-Type": "application/json"
            ],
            body: requestBody,
            providerName: "Anthropic Web Search"
        )

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let usage = json["usage"] as? [String: Any]
        let usageMetrics = makeUsage(
            prompt: intValue(usage?["input_tokens"]),
            completion: intValue(usage?["output_tokens"]),
            total: nil
        )

        let text = content
            .compactMap { block -> String? in
                guard let type = block["type"] as? String, type == "text" else { return nil }
                return block["text"] as? String
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let citations = extractAnthropicCitations(content)
            .filter { citation in
                domains.isEmpty || domains.contains(where: {
                    citation.urlString.localizedCaseInsensitiveContains($0)
                })
            }

        guard !text.isEmpty || !citations.isEmpty else {
            if let error = extractAnthropicToolError(content) {
                throw AIServiceError.apiError(error)
            }
            throw AIServiceError.invalidResponse
        }

        return AIWebSearchResponse(text: text, citations: citations, usage: usageMetrics)
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

    private static func groundedWebSearchGemini(
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse {
        var prompt = query
        if !domains.isEmpty {
            let domainQuery = domains.map { "site:\($0)" }.joined(separator: " OR ")
            prompt += "\nFocus on these domains when relevant: \(domainQuery)"
        }
        if let systemPrompt, !systemPrompt.isEmpty {
            prompt = "\(systemPrompt)\n\n\(prompt)"
        }

        let requestBody: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "tools": [
                ["google_search": [:]]
            ],
            "generationConfig": [
                "maxOutputTokens": maxTokens,
                "temperature": 0.2
            ]
        ]

        let data = try await sendRequest(
            url: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent",
            headers: [
                "Content-Type": "application/json",
                "x-goog-api-key": apiKey
            ],
            body: requestBody,
            providerName: "Gemini Web Search"
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

        let text = candidates
            .compactMap { candidate -> String? in
                guard let content = candidate["content"] as? [String: Any],
                      let parts = content["parts"] as? [[String: Any]] else {
                    return nil
                }
                return parts.compactMap { $0["text"] as? String }.joined(separator: "\n")
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let citations = extractGeminiCitations(candidates)
            .filter { citation in
                domains.isEmpty || domains.contains(where: {
                    citation.urlString.localizedCaseInsensitiveContains($0)
                })
            }

        guard !text.isEmpty || !citations.isEmpty else {
            throw AIServiceError.invalidResponse
        }

        return AIWebSearchResponse(text: text, citations: citations, usage: usageMetrics)
    }

    // MARK: - Shared HTTP

    private static func sendRequest(
        url: String,
        headers: [String: String],
        body: [String: Any],
        providerName: String
    ) async throws -> Data {
        try await AIRequestRetry.withRetry {
            try await sendRequestOnce(
                url: url,
                headers: headers,
                body: body,
                providerName: providerName
            )
        }
    }

    private static func sendRequestOnce(
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
                // Prefix with status code so isRetryable can identify 5xx errors.
                throw AIServiceError.apiError("[\(httpResponse.statusCode)] \(message)")
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

    private static func makeWebSearchInput(
        query: String,
        systemPrompt: String?
    ) -> [[String: Any]] {
        var input: [[String: Any]] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            input.append([
                "role": "system",
                "content": [["type": "input_text", "text": systemPrompt]]
            ])
        }
        input.append([
            "role": "user",
            "content": [["type": "input_text", "text": query]]
        ])
        return input
    }

    private static func extractOpenAIResponseText(_ json: [String: Any]) -> String {
        if let outputText = json["output_text"] as? String, !outputText.isEmpty {
            return outputText
        }

        guard let output = json["output"] as? [[String: Any]] else {
            return ""
        }

        let text = output.flatMap { item -> [String] in
            if let content = item["content"] as? [[String: Any]] {
                return content.compactMap { contentItem in
                    if let text = contentItem["text"] as? String {
                        return text
                    }
                    return nil
                }
            }
            return []
        }
        .joined(separator: "\n")

        return text
    }

    private static func extractOpenAICitations(_ json: [String: Any]) -> [AIWebSearchCitation] {
        guard let output = json["output"] as? [[String: Any]] else { return [] }
        var citations: [AIWebSearchCitation] = []

        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for contentItem in content {
                let snippet = contentItem["text"] as? String
                guard let annotations = contentItem["annotations"] as? [[String: Any]] else { continue }
                for annotation in annotations {
                    let type = annotation["type"] as? String
                    guard type == "url_citation" || annotation["url"] != nil else { continue }
                    guard let urlString = annotation["url"] as? String else { continue }
                    let title = (annotation["title"] as? String)
                        ?? (annotation["source_title"] as? String)
                        ?? URL(string: urlString)?.host
                        ?? "Source"
                    citations.append(
                        AIWebSearchCitation(
                            title: title,
                            urlString: urlString,
                            snippet: snippet,
                            sourceDomain: URL(string: urlString)?.host,
                            rawPayload: jsonString(annotation)
                        )
                    )
                }
            }
        }

        return deduplicatedCitations(citations)
    }

    private static func extractAnthropicCitations(_ content: [[String: Any]]) -> [AIWebSearchCitation] {
        var citations: [AIWebSearchCitation] = []

        for block in content {
            let snippet = block["text"] as? String
            guard let blockCitations = block["citations"] as? [[String: Any]] else { continue }
            for citation in blockCitations {
                let urlString = (citation["url"] as? String)
                    ?? (citation["uri"] as? String)
                    ?? (citation["source"] as? [String: Any])?["url"] as? String
                guard let urlString else { continue }
                let title = (citation["title"] as? String)
                    ?? (citation["source"] as? [String: Any])?["title"] as? String
                    ?? URL(string: urlString)?.host
                    ?? "Source"
                citations.append(
                    AIWebSearchCitation(
                        title: title,
                        urlString: urlString,
                        snippet: snippet,
                        sourceDomain: URL(string: urlString)?.host,
                        rawPayload: jsonString(citation)
                    )
                )
            }
        }

        return deduplicatedCitations(citations)
    }

    private static func extractAnthropicToolError(_ content: [[String: Any]]) -> String? {
        for block in content {
            guard let type = block["type"] as? String else { continue }
            if type.contains("error"), let message = block["text"] as? String {
                return message
            }
        }
        return nil
    }

    private static func extractGeminiCitations(_ candidates: [[String: Any]]) -> [AIWebSearchCitation] {
        var citations: [AIWebSearchCitation] = []

        for candidate in candidates {
            guard let groundingMetadata = candidate["groundingMetadata"] as? [String: Any] else { continue }
            let chunks = groundingMetadata["groundingChunks"] as? [[String: Any]] ?? []
            let supports = groundingMetadata["groundingSupports"] as? [[String: Any]] ?? []

            var snippetsByIndex: [Int: String] = [:]
            for support in supports {
                let snippet = (support["segment"] as? [String: Any])?["text"] as? String
                let chunkIndices = support["groundingChunkIndices"] as? [Int] ?? []
                for index in chunkIndices {
                    if let snippet, snippetsByIndex[index] == nil {
                        snippetsByIndex[index] = snippet
                    }
                }
            }

            for (index, chunk) in chunks.enumerated() {
                let web = chunk["web"] as? [String: Any]
                guard let urlString = web?["uri"] as? String else { continue }
                let title = (web?["title"] as? String)
                    ?? URL(string: urlString)?.host
                    ?? "Source"
                citations.append(
                    AIWebSearchCitation(
                        title: title,
                        urlString: urlString,
                        snippet: snippetsByIndex[index],
                        sourceDomain: URL(string: urlString)?.host,
                        rawPayload: jsonString(chunk)
                    )
                )
            }
        }

        return deduplicatedCitations(citations)
    }

    private static func deduplicatedCitations(_ citations: [AIWebSearchCitation]) -> [AIWebSearchCitation] {
        var seen: Set<String> = []
        var result: [AIWebSearchCitation] = []

        for citation in citations {
            let key = citation.urlString.lowercased()
            if seen.insert(key).inserted {
                result.append(citation)
            }
        }

        return result
    }

    private static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }
}
