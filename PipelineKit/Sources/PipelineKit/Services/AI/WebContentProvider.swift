import Foundation

/// Protocol for fetching text content from URLs.
/// The app target provides a WKWebView-backed implementation;
/// CLI targets can provide a URLSession-only implementation.
public struct WebContentFetchResult: Sendable, Equatable {
    public let text: String
    public let acquisitionMethod: ResearchAcquisitionMethod
    public let resolvedURLString: String?

    public init(
        text: String,
        acquisitionMethod: ResearchAcquisitionMethod,
        resolvedURLString: String? = nil
    ) {
        self.text = text
        self.acquisitionMethod = acquisitionMethod
        self.resolvedURLString = resolvedURLString
    }
}

public protocol WebContentProvider: Sendable {
    func fetchContent(from url: String) async throws -> WebContentFetchResult
}

public extension WebContentProvider {
    func fetchText(from url: String) async throws -> String {
        try await fetchContent(from: url).text
    }
}

/// Basic URLSession-only web content provider.
public final class BasicWebContentProvider: WebContentProvider {
    private let serviceName: String

    public init(serviceName: String = "BasicWebContentProvider") {
        self.serviceName = serviceName
    }

    public func fetchContent(from urlString: String) async throws -> WebContentFetchResult {
        guard let url = URL(string: urlString) else {
            throw AIServiceError.invalidURL
        }

        AIParseDebugLogger.info(
            "\(serviceName): fetching webpage \(AIParseDebugLogger.summarizedURL(urlString))."
        )

        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 30

        let (data, response) = try await AIRequestRetry.withRetry { () async throws -> (Data, URLResponse) in
            let (d, r): (Data, URLResponse)
            do {
                (d, r) = try await URLSession.shared.data(for: request)
            } catch {
                AIParseDebugLogger.error(
                    "\(serviceName): network error fetching webpage: \(error.localizedDescription)."
                )
                throw AIServiceError.networkError(error)
            }

            if let httpResponse = r as? HTTPURLResponse {
                AIParseDebugLogger.info(
                    "\(serviceName): webpage fetch status=\(httpResponse.statusCode) bytes=\(d.count)."
                )

                if !(200...299).contains(httpResponse.statusCode) {
                    // Prefix with [statusCode] so isRetryable can identify 5xx errors.
                    throw AIServiceError.apiError(
                        "[\(httpResponse.statusCode)] Job URL returned HTTP \(httpResponse.statusCode)."
                    )
                }
            }

            return (d, r)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw AIServiceError.parsingError("Failed to decode webpage")
        }

        let text = Self.stripHTML(html)
        AIParseDebugLogger.info(
            "\(serviceName): stripped webpage text length=\(text.count)."
        )

        guard !text.isEmpty else {
            throw AIServiceError.parsingError("Webpage content was empty after HTML stripping.")
        }

        return WebContentFetchResult(
            text: text,
            acquisitionMethod: .urlSession,
            resolvedURLString: response.url?.absoluteString ?? url.absoluteString
        )
    }

    public static func stripHTML(_ html: String) -> String {
        var text = html

        text = text.replacingOccurrences(of: "<script[^>]*>[\\s\\S]*?</script>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<style[^>]*>[\\s\\S]*?</style>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")

        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count > Constants.Limits.webContentMaxLength {
            text = String(text.prefix(Constants.Limits.webContentMaxLength))
        }

        return text
    }
}
