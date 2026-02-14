import Foundation

public final class ModelCatalogService {
    public static let shared = ModelCatalogService()

    private init() {}

    public func fetchModels(for provider: AIProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .openAI:
            return try await fetchOpenAIModels(apiKey: apiKey)
        case .anthropic:
            return try await fetchAnthropicModels(apiKey: apiKey)
        case .gemini:
            return try await fetchGeminiModels(apiKey: apiKey)
        }
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isOpenAIChatCompatibleModel($0) }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func fetchAnthropicModels(apiKey: String) async throws -> [String] {
        guard let url = URL(string: "https://api.anthropic.com/v1/models") else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { $0["id"] as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().contains("claude") }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [String] {
        guard var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models") else {
            throw AIServiceError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "key", value: apiKey)
        ]

        guard let url = components.url else {
            throw AIServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let data = try await requestData(request, unauthorizedStatusCodes: [401, 403])

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else {
            throw AIServiceError.invalidResponse
        }

        let modelIDs = models
            .compactMap { model -> String? in
                guard let name = model["name"] as? String else { return nil }

                let methods = model["supportedGenerationMethods"] as? [String] ?? []
                guard methods.contains("generateContent") else { return nil }

                if name.hasPrefix("models/") {
                    return String(name.dropFirst("models/".count))
                }

                return name
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.lowercased().contains("gemini") }
            .uniquedPreservingOrder()

        return modelIDs
    }

    private func requestData(
        _ request: URLRequest,
        unauthorizedStatusCodes: Set<Int>
    ) async throws -> Data {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }

        if unauthorizedStatusCodes.contains(httpResponse.statusCode) {
            throw AIServiceError.unauthorized
        }

        if httpResponse.statusCode == 429 {
            throw AIServiceError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = extractErrorMessage(from: data) ?? "HTTP \(httpResponse.statusCode)"
            throw AIServiceError.apiError(message)
        }

        return data
    }

    private func extractErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String,
           !message.isEmpty {
            return message
        }

        if let message = json["message"] as? String,
           !message.isEmpty {
            return message
        }

        return nil
    }

    private func isOpenAIChatCompatibleModel(_ modelID: String) -> Bool {
        let lower = modelID.lowercased()

        let disallowedSubstrings = [
            "embedding",
            "whisper",
            "transcribe",
            "tts",
            "audio",
            "realtime",
            "image",
            "moderation",
            "dall-e",
            "search",
            "rerank"
        ]

        if disallowedSubstrings.contains(where: lower.contains) {
            return false
        }

        if lower.hasPrefix("gpt") || lower.hasPrefix("chatgpt") {
            return true
        }

        if lower.range(of: #"^o\d"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }
}

// MARK: - Array Extension

public extension Array where Element: Hashable {
    func uniquedPreservingOrder() -> [Element] {
        var seen = Set<Element>()
        var result: [Element] = []
        result.reserveCapacity(count)
        for value in self where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}
