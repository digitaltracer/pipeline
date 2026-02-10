import Foundation
import OSLog
#if canImport(WebKit)
import WebKit
#endif

// MARK: - Protocol

protocol AIServiceProtocol {
    func parseJobPosting(from url: String, model: String) async throws -> AIParsingViewModel.ParsedJobData
}

// MARK: - Errors

enum AIServiceError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case parsingError(String)
    case invalidResponse
    case apiError(String)
    case rateLimited
    case unauthorized
    case noDataExtracted

    var errorDescription: String? {
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
            return "AI returned a response, but no job details were extracted. Check the Xcode console logs for \"AIParse\" entries."
        }
    }
}

// MARK: - Debug Logging

enum AIParseDebugLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Pipeline",
        category: "AIParse"
    )

    static func info(_ message: String) {
        #if DEBUG
        logger.info("\(message, privacy: .public)")
        #endif
    }

    static func warning(_ message: String) {
        #if DEBUG
        logger.warning("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        #if DEBUG
        logger.error("\(message, privacy: .public)")
        #endif
    }

    static func infoFullText(_ label: String, text: String, chunkSize: Int = 1200) {
        #if DEBUG
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty else {
            logger.info("\(label, privacy: .public): <empty>")
            return
        }

        logger.info("\(label, privacy: .public): full text length=\(normalized.count, privacy: .public).")

        var part = 1
        var cursor = normalized.startIndex
        while cursor < normalized.endIndex {
            let next = normalized.index(cursor, offsetBy: chunkSize, limitedBy: normalized.endIndex) ?? normalized.endIndex
            let chunk = String(normalized[cursor..<next])
            logger.info("\(label, privacy: .public) [part \(part, privacy: .public)]: \(chunk, privacy: .public)")
            cursor = next
            part += 1
        }
        #endif
    }

    static func preview(_ text: String, maxLength: Int = 280) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > maxLength else {
            return compact
        }
        return "\(compact.prefix(maxLength))..."
    }

    static func summarizedURL(_ rawURL: String) -> String {
        guard let url = URL(string: rawURL) else {
            return rawURL
        }

        let host = url.host ?? "unknown-host"
        let path = url.path.isEmpty ? "/" : url.path
        return "\(host)\(path)"
    }
}

// MARK: - Web Content Fetching

enum WebContentFetcher {
    private static let blockedStatusCodes: Set<Int> = [403, 429, 999]

    static func fetchText(from urlString: String, serviceName: String) async throws -> String {
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

            if blockedStatusCodes.contains(httpResponse.statusCode) {
                return try await fetchTextWithWebView(
                    from: url,
                    serviceName: serviceName,
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

        let text = stripHTML(html)
        AIParseDebugLogger.info(
            "\(serviceName): stripped webpage text length=\(text.count) preview=\(AIParseDebugLogger.preview(text, maxLength: 220))."
        )

        if text.isEmpty {
            return try await fetchTextWithWebView(
                from: url,
                serviceName: serviceName,
                reason: "empty URLSession extraction"
            )
        }

        return text
    }

    private static func stripHTML(_ html: String) -> String {
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

        if text.count > 15000 {
            text = String(text.prefix(15000))
        }

        return text
    }

    private static func normalizeExtractedText(_ rawText: String) -> String {
        var text = rawText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 15000 {
            text = String(text.prefix(15000))
        }
        return text
    }

    private static func fetchTextWithWebView(
        from url: URL,
        serviceName: String,
        reason: String
    ) async throws -> String {
        #if canImport(WebKit)
        AIParseDebugLogger.warning(
            "\(serviceName): falling back to WKWebView extraction due to \(reason)."
        )

        let rawText = try await WebViewTextExtractor(serviceName: serviceName).extractText(from: url)
        let normalizedText = normalizeExtractedText(rawText)

        AIParseDebugLogger.info(
            "\(serviceName): WKWebView extracted text length=\(normalizedText.count) preview=\(AIParseDebugLogger.preview(normalizedText, maxLength: 220))."
        )
        AIParseDebugLogger.infoFullText(
            "\(serviceName): WKWebView extracted text",
            text: normalizedText
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
                // Give dynamic sites a brief moment to hydrate content.
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

// MARK: - Common Prompt

enum AIServicePrompts {
    static let jobParsingPrompt = """
    You are extracting structured job posting data.

    Return exactly one valid JSON object with this schema and field names:
    {
      "companyName": string,
      "role": string,
      "location": string,
      "jobDescription": string,
      "salaryMin": number|null,
      "salaryMax": number|null,
      "currency": "USD"|"INR"|"EUR"|"GBP"
    }

    Rules:
    - Use empty strings for unknown string fields.
    - Use null for unknown salary fields.
    - Salary numbers must be annual base units as plain integers (example: 120000), not "120k" and no currency symbols.
    - Keep jobDescription concise and useful (maximum 1500 characters).
    - Include remote/hybrid details in location when present.
    - Do not include any fields other than the schema above.
    - Output raw JSON only. No markdown fences. No prose.
    """

    static func jobParsingUserPrompt(webContent: String) -> String {
        """
        Parse this job posting content:

        \(webContent)
        """
    }
}

// MARK: - Response Parsing Helper

enum AIResponseParser {
    static func parseJobData(from jsonString: String) throws -> AIParsingViewModel.ParsedJobData {
        AIParseDebugLogger.info("AIResponseParser: received model output (\(jsonString.count) chars).")

        let cleaned = stripMarkdownFences(from: jsonString)
        let jsonPayload = extractJSONObject(from: cleaned) ?? cleaned

        guard let root = parseJSONObject(from: jsonPayload) else {
            let preview = AIParseDebugLogger.preview(jsonPayload, maxLength: 600)
            AIParseDebugLogger.error("AIResponseParser: unable to parse JSON payload. Preview: \(preview)")
            throw AIServiceError.parsingError("Model output was not valid JSON.")
        }

        let rootKeys = root.keys.sorted().joined(separator: ", ")
        AIParseDebugLogger.info("AIResponseParser: parsed JSON object keys = [\(rootKeys)].")

        let companyName = parseString(
            in: root,
            keys: ["companyName", "company", "company_name", "employer", "organization"]
        )
        let role = parseString(
            in: root,
            keys: ["role", "jobTitle", "job_title", "title", "position"]
        )
        let location = parseString(
            in: root,
            keys: ["location", "jobLocation", "job_location", "city", "place"]
        )
        let jobDescription = parseString(
            in: root,
            keys: ["jobDescription", "job_description", "description", "summary"]
        )

        var salaryMin = parseInt(
            in: root,
            keys: ["salaryMin", "salary_min", "minSalary", "min_salary", "salaryFrom", "salary_from"]
        )

        var salaryMax = parseInt(
            in: root,
            keys: ["salaryMax", "salary_max", "maxSalary", "max_salary", "salaryTo", "salary_to"]
        )

        let salaryText = parseString(
            in: root,
            keys: ["salary", "salaryRange", "salary_range", "compensation", "payRange", "pay_range"]
        )

        if !salaryText.isEmpty {
            let salaryNumbers = parseNumbers(from: salaryText)
            if salaryMin == nil {
                salaryMin = salaryNumbers.first
            }
            if salaryMax == nil, salaryNumbers.count > 1 {
                salaryMax = salaryNumbers[1]
            }
        }

        if let min = salaryMin, let max = salaryMax, min > max {
            swap(&salaryMin, &salaryMax)
        }

        var currencyRaw = parseString(
            in: root,
            keys: ["currency", "salaryCurrency", "salary_currency"]
        )
        if currencyRaw.isEmpty {
            currencyRaw = salaryText
        }
        if currencyRaw.isEmpty {
            currencyRaw = location
        }

        let result = AIParsingViewModel.ParsedJobData(
            companyName: companyName,
            role: role,
            location: location,
            jobDescription: jobDescription,
            salaryMin: salaryMin,
            salaryMax: salaryMax,
            currency: parseCurrency(from: currencyRaw)
        )

        let hasAnyField = !result.companyName.isEmpty ||
            !result.role.isEmpty ||
            !result.location.isEmpty ||
            !result.jobDescription.isEmpty ||
            result.salaryMin != nil ||
            result.salaryMax != nil
        let descriptionLength = result.jobDescription.count
        AIParseDebugLogger.info(
            "AIResponseParser: extracted fields company=\(!result.companyName.isEmpty) role=\(!result.role.isEmpty) location=\(!result.location.isEmpty) descriptionChars=\(descriptionLength) salaryMin=\(String(describing: result.salaryMin)) salaryMax=\(String(describing: result.salaryMax)) hasAnyField=\(hasAnyField)."
        )

        return result
    }

    private static func parseCurrency(from rawValue: String?) -> Currency {
        let normalized = rawValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""

        if normalized.contains("INR") || normalized.contains("RUPEE") || normalized.contains("₹") {
            return .inr
        }
        if normalized.contains("EUR") || normalized.contains("EURO") || normalized.contains("€") {
            return .eur
        }
        if normalized.contains("GBP") || normalized.contains("POUND") || normalized.contains("£") {
            return .gbp
        }
        if normalized.contains("USD") || normalized.contains("DOLLAR") || normalized.contains("$") {
            return .usd
        }

        return .usd
    }

    private static func stripMarkdownFences(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(
            of: #"^```[a-zA-Z0-9_-]*\s*"#,
            with: "",
            options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: #"\s*```$"#,
            with: "",
            options: .regularExpression
        )
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseJSONObject(from raw: String) -> [String: Any]? {
        let candidates = jsonCandidates(from: raw)
        AIParseDebugLogger.info("AIResponseParser: trying \(candidates.count) JSON candidate payload(s).")

        for (index, candidate) in candidates.enumerated() {
            guard let data = candidate.data(using: .utf8) else { continue }

            if let object = try? JSONSerialization.jsonObject(with: data) {
                if let dictionary = object as? [String: Any] {
                    AIParseDebugLogger.info(
                        "AIResponseParser: candidate \(index + 1) parsed as object with \(dictionary.count) keys."
                    )
                    return dictionary
                }

                if let array = object as? [[String: Any]], let first = array.first {
                    AIParseDebugLogger.info(
                        "AIResponseParser: candidate \(index + 1) parsed as array; using first element."
                    )
                    return first
                }
            }
        }

        AIParseDebugLogger.warning("AIResponseParser: all JSON candidates failed to parse.")
        return nil
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String] = []

        func appendIfNeeded(_ value: String) {
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            if !candidates.contains(normalized) {
                candidates.append(normalized)
            }
        }

        appendIfNeeded(trimmed)

        var repaired = trimmed
            .replacingOccurrences(of: "“", with: "\"")
            .replacingOccurrences(of: "”", with: "\"")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: "’", with: "'")

        repaired = removeTrailingCommas(from: repaired)
        appendIfNeeded(repaired)

        if let repairedTruncated = repairPossiblyTruncatedJSONObject(from: trimmed) {
            appendIfNeeded(repairedTruncated)
        }

        if let repairedTruncated = repairPossiblyTruncatedJSONObject(from: repaired) {
            appendIfNeeded(repairedTruncated)
        }

        if let extracted = extractJSONObject(from: trimmed) {
            appendIfNeeded(extracted)
        }

        if let extracted = extractJSONObject(from: repaired) {
            appendIfNeeded(extracted)
        }

        return candidates
    }

    /// Attempts to repair truncated JSON object text by closing an unterminated string and/or braces.
    /// This helps recover partially cut-off model outputs.
    private static func repairPossiblyTruncatedJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIndex = trimmed.firstIndex(of: "{") else { return nil }

        var candidate = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for character in candidate {
            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                depth += 1
            } else if character == "}" {
                depth -= 1
            }
        }

        if isInsideString {
            if isEscaped {
                candidate.append("\\")
            }
            candidate.append("\"")
        }

        if depth > 0 {
            candidate.append(String(repeating: "}", count: depth))
        }

        return removeTrailingCommas(from: candidate)
    }

    private static func removeTrailingCommas(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #",\s*([}\]])"#) else {
            return text
        }

        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func parseString(in root: [String: Any], keys: [String]) -> String {
        for key in keys {
            guard let value = root[key] else { continue }

            if value is NSNull {
                continue
            }

            if let text = value as? String {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            } else if let number = value as? NSNumber {
                return number.stringValue
            }
        }

        return ""
    }

    private static func parseInt(in root: [String: Any], keys: [String]) -> Int? {
        for key in keys {
            guard let value = root[key] else { continue }
            if let parsed = parseIntValue(value) {
                return parsed
            }
        }

        return nil
    }

    private static func parseIntValue(_ value: Any) -> Int? {
        if value is NSNull {
            return nil
        }

        if let intValue = value as? Int {
            return intValue
        }

        if let doubleValue = value as? Double {
            return Int(doubleValue.rounded())
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let stringValue = value as? String {
            return parseInt(from: stringValue)
        }

        return nil
    }

    private static func parseInt(from raw: String) -> Int? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return nil }

        let sanitized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")

        if let intValue = Int(sanitized) {
            return intValue
        }

        if let doubleValue = Double(sanitized) {
            return Int(doubleValue.rounded())
        }

        let compact = sanitized.replacingOccurrences(of: " ", with: "")
        if let suffixed = parseWithSuffix(compact) {
            return suffixed
        }

        let pattern = #"-?\d+(?:\.\d+)?(?:[kmb])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: compact,
                range: NSRange(compact.startIndex..., in: compact)
              ),
              let range = Range(match.range, in: compact) else {
            return nil
        }

        return parseWithSuffix(String(compact[range]))
    }

    private static func parseNumbers(from raw: String) -> [Int] {
        let compact = raw
            .lowercased()
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "₹", with: "")
            .replacingOccurrences(of: "€", with: "")
            .replacingOccurrences(of: "£", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard !compact.isEmpty else { return [] }

        let pattern = #"-?\d+(?:\.\d+)?(?:[kmb])?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }

        let matches = regex.matches(in: compact, range: NSRange(compact.startIndex..., in: compact))
        var values: [Int] = []

        for match in matches {
            guard let range = Range(match.range, in: compact) else { continue }
            let token = String(compact[range])

            if let value = parseWithSuffix(token) {
                values.append(value)
            }

            if values.count >= 2 {
                break
            }
        }

        return values
    }

    private static func parseWithSuffix(_ token: String) -> Int? {
        guard !token.isEmpty else { return nil }

        let lower = token.lowercased()
        let last = lower.last
        let multiplier: Double
        let numberPortion: String

        switch last {
        case "k":
            multiplier = 1_000
            numberPortion = String(lower.dropLast())
        case "m":
            multiplier = 1_000_000
            numberPortion = String(lower.dropLast())
        case "b":
            multiplier = 1_000_000_000
            numberPortion = String(lower.dropLast())
        default:
            multiplier = 1
            numberPortion = lower
        }

        if let intValue = Int(numberPortion), multiplier == 1 {
            return intValue
        }

        guard let numeric = Double(numberPortion) else {
            return nil
        }

        return Int((numeric * multiplier).rounded())
    }

    /// Extract the first balanced JSON object from mixed text output.
    private static func extractJSONObject(from text: String) -> String? {
        var startIndex: String.Index?
        var depth = 0
        var isInsideString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInsideString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInsideString = false
                }
                continue
            }

            if character == "\"" {
                isInsideString = true
                continue
            }

            if character == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if character == "}", depth > 0 {
                depth -= 1
                if depth == 0, let startIndex {
                    return String(text[startIndex...index])
                }
            }
        }

        return nil
    }
}
