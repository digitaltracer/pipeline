import Foundation

final class GeminiService: AIServiceProtocol {
    private let apiKey: String
    private let baseURL = "https://generativelanguage.googleapis.com/v1beta/models"

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData {
        AIParseDebugLogger.info(
            "GeminiService: parse start url=\(AIParseDebugLogger.summarizedURL(url)) model=\(model)."
        )

        // First, fetch the webpage content
        let webContent = try await fetchWebContent(from: url)
        AIParseDebugLogger.info("GeminiService: fetched webpage text (\(webContent.count) chars).")

        guard !webContent.isEmpty else {
            AIParseDebugLogger.warning("GeminiService: webpage content is empty after HTML stripping.")
            throw AIServiceError.parsingError("Fetched page content was empty.")
        }

        // Build the request
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

        guard let url = URL(string: "\(baseURL)/\(model):generateContent") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
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

        // Parse the response
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
                "GeminiService: candidate \(index + 1) output captured."
            )
            AIParseDebugLogger.infoFullText(
                "GeminiService: candidate \(index + 1) output",
                text: text
            )

            do {
                return try AIResponseParser.parseJobData(from: text)
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

    private func fetchWebContent(from urlString: String) async throws -> String {
        try await WebContentFetcher.fetchText(from: urlString, serviceName: "GeminiService")
    }
}
