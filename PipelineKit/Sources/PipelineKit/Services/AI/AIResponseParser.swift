import Foundation

public enum AIResponseParser {
    public static func parseJobData(from jsonString: String) throws -> ParsedJobData {
        AIParseDebugLogger.info("AIResponseParser: received model output (\(jsonString.count) chars).")

        let cleaned = stripMarkdownFences(from: jsonString)
        let jsonPayload = extractJSONObject(from: cleaned) ?? cleaned

        guard let root = parseJSONObject(from: jsonPayload) else {
            AIParseDebugLogger.error(
                "AIResponseParser: unable to parse JSON payload. payloadChars=\(jsonPayload.count)."
            )
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

        let result = ParsedJobData(
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
            .replacingOccurrences(of: "\u{201C}", with: "\"")
            .replacingOccurrences(of: "\u{201D}", with: "\"")
            .replacingOccurrences(of: "\u{2018}", with: "'")
            .replacingOccurrences(of: "\u{2019}", with: "'")

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
