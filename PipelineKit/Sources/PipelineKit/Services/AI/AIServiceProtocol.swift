import Foundation
import OSLog

// MARK: - Protocol

public protocol AIServiceProtocol {
    func parseJobPosting(from url: String, model: String) async throws -> ParsedJobData
}

// MARK: - Errors

public enum AIServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case invalidResponse
    case apiError(String)
    case rateLimited
    case unauthorized
    case noDataExtracted

    /// Whether this error is transient and the request should be retried.
    public var isRetryable: Bool {
        switch self {
        case .rateLimited:
            return true
        case .networkError(let underlying):
            // Do not retry cancelled requests — the caller intentionally abandoned the work.
            if (underlying as? URLError)?.code == .cancelled {
                return false
            }
            return true
        case .apiError(let message):
            // Server errors (5xx) are retryable — check for the status code prefix
            // regardless of whether the provider returned a JSON error body.
            return message.hasPrefix("HTTP 5") || message.hasPrefix("[5")
        default:
            return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL provided"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .parsingError(let message):
            return "Failed to parse response: \(message)"
        case .invalidResponse:
            return "Invalid response from AI service"
        case .apiError(let message):
            return "API error: \(message)"
        case .rateLimited:
            return "Rate limited. Please try again later."
        case .unauthorized:
            return "Invalid API key. Please check your settings."
        case .noDataExtracted:
            return "AI returned a response, but no job details were extracted. Try another model or verify that the job page is readable."
        }
    }
}

// MARK: - Debug Logging

public enum AIParseDebugLogger {
    private static let logger = Logger(
        subsystem: Constants.App.bundleID,
        category: "AIParse"
    )

    public static func info(_ message: String) {
        #if DEBUG
        logger.info("\(message, privacy: .public)")
        #endif
    }

    public static func warning(_ message: String) {
        #if DEBUG
        logger.warning("\(message, privacy: .public)")
        #endif
    }

    public static func error(_ message: String) {
        #if DEBUG
        logger.error("\(message, privacy: .public)")
        #endif
    }

    public static func infoFullText(_ label: String, text: String, chunkSize: Int = 1200) {
        #if DEBUG
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else {
            logger.info("\(label, privacy: .public): content redacted; length=0.")
            return
        }

        logger.info(
            "\(label, privacy: .public): content redacted; length=\(normalized.count, privacy: .public) chunkSize=\(chunkSize, privacy: .public)."
        )
        #endif
    }

    public static func preview(_ text: String, maxLength: Int = 280) -> String {
        let compact = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "<empty>" }
        return "<redacted \(min(compact.count, maxLength)) chars>"
    }

    public static func summarizedURL(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL) else {
            return rawURL
        }

        let host = url.host ?? "unknown-host"
        let path = url.path.isEmpty ? "/" : url.path
        return "\(host)\(path)"
    }
}

// MARK: - Retry with Exponential Backoff

public enum AIRequestRetry {
    /// Maximum number of retry attempts for transient failures.
    public static let maxRetries = 2

    /// Base delay in seconds (doubled on each retry with jitter).
    private static let baseDelay: Double = 1.0

    /// Execute an async throwing closure with retry logic and exponential backoff.
    /// Only retries on `AIServiceError` where `isRetryable` is true.
    /// Parses the `Retry-After` header delay when available via the returned error context.
    public static func withRetry<T>(
        maxAttempts: Int = maxRetries + 1,
        operation: () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch let error as AIServiceError where error.isRetryable {
                lastError = error
                let isLastAttempt = attempt == maxAttempts - 1
                guard !isLastAttempt, !Task.isCancelled else { break }

                let delay = backoffDelay(attempt: attempt, error: error)
                AIParseDebugLogger.warning(
                    "Retry \(attempt + 1)/\(maxAttempts - 1): \(error.localizedDescription). Waiting \(String(format: "%.1f", delay))s."
                )
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                // If the task was cancelled during the backoff sleep, stop immediately.
                guard !Task.isCancelled else { break }
            } catch {
                throw error
            }
        }
        throw lastError!
    }

    private static func backoffDelay(attempt: Int, error: AIServiceError) -> Double {
        let exponential = baseDelay * pow(2.0, Double(attempt))
        let jitter = Double.random(in: 0...(exponential * 0.3))
        return exponential + jitter
    }
}

// MARK: - Shared HTTP Helper for AI Services

public enum AIHTTPClient {
    /// Sends an HTTP request and maps non-success status codes to `AIServiceError`.
    /// Used by individual AI service implementations (OpenAI, Anthropic, Gemini).
    public static func send(
        _ request: URLRequest,
        serviceName: String
    ) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AIParseDebugLogger.error("\(serviceName): network error: \(error.localizedDescription).")
            throw AIServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            AIParseDebugLogger.error("\(serviceName): missing HTTP response.")
            throw AIServiceError.invalidResponse
        }

        AIParseDebugLogger.info(
            "\(serviceName): HTTP \(httpResponse.statusCode) bytes=\(data.count)."
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
                AIParseDebugLogger.error("\(serviceName): API error status=\(httpResponse.statusCode) message=\(message).")
                // Prefix with status code so isRetryable can identify 5xx errors.
                throw AIServiceError.apiError("[\(httpResponse.statusCode)] \(message)")
            }
            AIParseDebugLogger.error("\(serviceName): API error status=\(httpResponse.statusCode).")
            throw AIServiceError.apiError("HTTP \(httpResponse.statusCode)")
        }
    }
}
