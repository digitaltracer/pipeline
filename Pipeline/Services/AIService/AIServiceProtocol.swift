// AI protocol, errors, debug logger, prompts, and response parser are now in PipelineKit.
// This file retains only the WKWebView-backed WebContentFetcher for the app target.

import Foundation
import PipelineKit
#if canImport(WebKit)
import WebKit
#endif

/// App-level WebContentProvider that falls back to WKWebView for blocked sites.
final class WKWebViewContentProvider: WebContentProvider {
    private let serviceName: String

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func fetchText(from urlString: String) async throws -> String {
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

            let blockedStatusCodes: Set<Int> = [403, 429, 999]
            if blockedStatusCodes.contains(httpResponse.statusCode) {
                return try await fetchTextWithWebView(
                    from: url,
                    reason: "HTTP \(httpResponse.statusCode)"
                )
            }

            if !(200...299).contains(httpResponse.statusCode) {
                throw AIServiceError.apiError(
                    "Job URL returned HTTP \(httpResponse.statusCode)."
                )
            }
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw AIServiceError.parsingError("Failed to decode webpage")
        }

        let text = BasicWebContentProvider.stripHTML(html)
        AIParseDebugLogger.info(
            "\(serviceName): stripped webpage text length=\(text.count)."
        )

        if text.isEmpty {
            return try await fetchTextWithWebView(
                from: url,
                reason: "empty URLSession extraction"
            )
        }

        return text
    }

    private func normalizeExtractedText(_ rawText: String) -> String {
        var text = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > Constants.Limits.webContentMaxLength {
            text = String(text.prefix(Constants.Limits.webContentMaxLength))
        }
        return text
    }

    private func fetchTextWithWebView(
        from url: URL,
        reason: String
    ) async throws -> String {
        #if canImport(WebKit)
        AIParseDebugLogger.warning(
            "\(serviceName): falling back to WKWebView extraction due to \(reason)."
        )

        let rawText = try await WebViewTextExtractor(serviceName: serviceName).extractText(from: url)
        let normalizedText = normalizeExtractedText(rawText)

        AIParseDebugLogger.info(
            "\(serviceName): WKWebView extracted text length=\(normalizedText.count)."
        )

        guard !normalizedText.isEmpty else {
            throw AIServiceError.parsingError("WebView extraction returned empty page content.")
        }

        return normalizedText
        #else
        throw AIServiceError.apiError("Job URL seems blocked and WKWebView fallback is unavailable.")
        #endif
    }
}

#if canImport(WebKit)
@MainActor
private final class WebViewTextExtractor: NSObject, WKNavigationDelegate {
    private let serviceName: String
    private var continuation: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var webView: WKWebView?
    private var completed = false

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func extractText(from url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation

            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
            self.webView = webView

            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            webView.load(request)

            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 25_000_000_000)
                guard let self else { return }
                self.finish(
                    with: .failure(
                        AIServiceError.parsingError("Timed out loading page in WKWebView.")
                    )
                )
            }
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)

                let javascript = """
                (() => {
                    const selectors = [
                        'main',
                        'article',
                        '[role="main"]',
                        '.jobs-description-content__text',
                        '.description',
                        '.job-description'
                    ];
                    for (const selector of selectors) {
                        const node = document.querySelector(selector);
                        if (node && node.innerText && node.innerText.trim().length > 0) {
                            return node.innerText;
                        }
                    }
                    return document.body ? document.body.innerText : '';
                })();
                """

                let evaluated = try await webView.evaluateJavaScript(javascript)
                let text = evaluated as? String ?? ""
                self.finish(with: .success(text))
            } catch {
                self.finish(
                    with: .failure(
                        AIServiceError.parsingError(
                            "WKWebView JavaScript extraction failed: \(error.localizedDescription)"
                        )
                    )
                )
            }
        }
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { [weak self] in
            guard let self else { return }
            AIParseDebugLogger.error(
                "\(serviceName): WKWebView navigation failed: \(error.localizedDescription)."
            )
            self.finish(with: .failure(AIServiceError.networkError(error)))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { [weak self] in
            guard let self else { return }
            AIParseDebugLogger.error(
                "\(serviceName): WKWebView provisional navigation failed: \(error.localizedDescription)."
            )
            self.finish(with: .failure(AIServiceError.networkError(error)))
        }
    }

    private func finish(with result: Result<String, Error>) {
        guard !completed else { return }
        completed = true

        timeoutTask?.cancel()
        timeoutTask = nil

        webView?.navigationDelegate = nil
        webView?.stopLoading()
        webView = nil

        continuation?.resume(with: result)
        continuation = nil
    }
}
#endif
