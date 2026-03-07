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
