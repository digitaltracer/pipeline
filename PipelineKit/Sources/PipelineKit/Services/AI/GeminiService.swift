import Foundation

public final class GeminiService: AIServiceProtocol {
    private let apiKey: String
    private let contentProvider: WebContentProvider
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    public init(apiKey: String, contentProvider: WebContentProvider = BasicWebContentProvider(serviceName: "GeminiService")) {
        self.apiKey = apiKey
        self.contentProvider = contentProvider
    }

    public func parseJobPosting(from url: String, model: String) async throws -> ParsedJobData {
        AIParseDebugLogger.info(
            "GeminiService: parse start url=\(AIParseDebugLogger.summarizedURL(url)) model=\(model)."
        )

        let webContent = try await contentProvider.fetchText(from: url)
        AIParseDebugLogger.info("GeminiService: fetched webpage text (\(webContent.count) chars).")

        guard !webContent.isEmpty else {
            AIParseDebugLogger.warning("GeminiService: webpage content is empty after HTML stripping.")
            throw AIServiceError.parsingError("Fetched page content was empty.")
        }

        let prompt = "\(AIServicePrompts.jobParsingPrompt)\n\n\(AIServicePrompts.jobParsingUserPrompt(webContent: webContent))"

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": 0.1,
                "maxOutputTokens": 2000,
                "responseMimeType": "application/json"
            ]
        ]

        guard let requestURL = URL(string: "\(baseURL)/\(model):generateContent") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AIParseDebugLogger.error("GeminiService: network error during Gemini call: \(error.localizedDescription).")
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AIParseDebugLogger.error("GeminiService: missing HTTP response from Gemini.")
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info(
            "GeminiService: Gemini response status=\(httpResponse.statusCode) bytes=\(data.count)."
        )

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw AIServiceError.unauthorized
        case 429:
            throw AIServiceError.rateLimited
        default:
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = errorJson["error"] as? [String: Any],
               let message = error["message"] as? String {
                AIParseDebugLogger.error(
                    "GeminiService: API error status=\(httpResponse.statusCode) message=\(message)."
                )
                throw AIServiceError.apiError(message)
            }
            AIParseDebugLogger.error("GeminiService: API error status=\(httpResponse.statusCode).")
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw AIServiceError.parsingError("Unable to decode Gemini response.")
        }

        guard let json = jsonObject as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              !candidates.isEmpty else {
            AIParseDebugLogger.error("GeminiService: response JSON missing expected fields.")
            throw AIServiceError.invalidResponse
        }
        let usage = json["usageMetadata"] as? [String: Any]
        let usageMetrics = AIUsageMetrics(
            promptTokens: intValue(usage?["promptTokenCount"]),
            completionTokens: intValue(usage?["candidatesTokenCount"]),
            totalTokens: intValue(usage?["totalTokenCount"])
        )

        var parseError: Error?

        for (index, candidate) in candidates.enumerated() {
            guard let content = candidate["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                continue
            }

            let text = parts
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else { continue }

            AIParseDebugLogger.info(
                "GeminiService: candidate \(index + 1) output chars=\(text.count)."
            )

            do {
                var parsed = try AIResponseParser.parseJobData(from: text)
                parsed.usage = usageMetrics
                return parsed
            } catch {
                parseError = error
                AIParseDebugLogger.warning(
                    "GeminiService: candidate \(index + 1) failed to parse; trying next candidate if available."
                )
            }
        }

        if let parseError {
            throw parseError
        }

        AIParseDebugLogger.error("GeminiService: no candidate contained parseable text output.")
        throw AIServiceError.invalidResponse
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
