import Foundation

/// Protocol for fetching text content from URLs.
/// The app target provides a WKWebView-backed implementation;
/// CLI targets can provide a URLSession-only implementation.
public protocol WebContentProvider: Sendable {
    func fetchText(from url: String) async throws -> String
}

/// Basic URLSession-only web content provider.
public final class BasicWebContentProvider: WebContentProvider {
    private let serviceName: String

    public init(serviceName: String = "BasicWebContentProvider") {
        self.serviceName = serviceName
    }

    public func fetchText(from urlString: String) async throws -> String {
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

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            AIParseDebugLogger.error(
                "\(serviceName): network error fetching webpage: \(error.localizedDescription)."
            )
            throw AIServiceError.networkError(error)
        }

        if let httpResponse = response as? HTTPURLResponse {
            AIParseDebugLogger.info(
                "\(serviceName): webpage fetch status=\(httpResponse.statusCode) bytes=\(data.count)."
            )

            if !(200...299).contains(httpResponse.statusCode) {
                throw AIServiceError.apiError(
                    "Job URL returned HTTP \(httpResponse.statusCode)."
                )
            }
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw AIServiceError.parsingError("Failed to decode webpage")
        }

        let text = Self.stripHTML(html)
        AIParseDebugLogger.info(
            "\(serviceName): stripped webpage text length=\(text.count) preview=\(AIParseDebugLogger.preview(text, maxLength: 220))."
        )

        guard !text.isEmpty else {
            throw AIServiceError.parsingError("Webpage content was empty after HTML stripping.")
        }

        return text
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
