import Foundation

public enum ResumeTailoringService {
    private static let invalidJSONErrorMessage =
        "Resume tailoring response was not valid JSON. Check Xcode console logs for \"AIParse\" entries."
    private static let schemaMismatchErrorMessage =
        "Resume tailoring response JSON did not match expected schema. Check Xcode console logs for \"AIParse\" entries."
    private static let truncatedResponseErrorMessage =
        "Resume tailoring response appears truncated before JSON completed. Please retry Generate Suggestions and check AIParse logs."
    private static let tailoringMaxTokens = 25_000

    public static func generateSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String
    ) async throws -> ResumeTailoringResult {
        AIParseDebugLogger.info(
            "ResumeTailoringService: generating suggestions provider=\(provider.rawValue) model=\(model) resumeChars=\(resumeJSON.count) jobDescriptionChars=\(jobDescription.count)."
        )

        let userPrompt = ResumeTailoringPrompts.userPrompt(
            resumeJSON: resumeJSON,
            company: company,
            role: role,
            jobDescription: jobDescription
        )

        let attemptPrompts = [
            ResumeTailoringPrompts.systemPrompt,
            ResumeTailoringPrompts.compactRetrySystemPrompt
        ]

        for attemptIndex in attemptPrompts.indices {
            let systemPrompt = attemptPrompts[attemptIndex]
            let isRetryAttempt = attemptIndex > 0

            if isRetryAttempt {
                AIParseDebugLogger.warning(
                    "ResumeTailoringService: retrying with compact prompt after truncated response."
                )
            }

            let raw = try await AICompletionClient.complete(
                provider: provider,
                apiKey: apiKey,
                model: model,
                systemPrompt: systemPrompt,
                userPrompt: userPrompt,
                maxTokens: tailoringMaxTokens,
                temperature: isRetryAttempt ? 0.2 : 0.3
            )

            do {
                return try parseResult(from: raw)
            } catch {
                guard isRetryableTruncationError(error), !isRetryAttempt else {
                    throw error
                }
            }
        }

        throw AIServiceError.parsingError(truncatedResponseErrorMessage)
    }

    public static func parseResult(from rawResponse: String) throws -> ResumeTailoringResult {
        AIParseDebugLogger.info(
            "ResumeTailoringService: received model output (\(rawResponse.count) chars)."
        )

        let cleaned = stripMarkdownFences(from: rawResponse)
        let candidates = jsonCandidates(from: cleaned)

        AIParseDebugLogger.info(
            "ResumeTailoringService: trying \(candidates.count) JSON candidate payload(s)."
        )

        var sawValidJSONCandidate = false
        var lastDecodeError: Error?

        for (index, candidate) in candidates.enumerated() {
            guard let data = candidate.data(using: .utf8) else {
                continue
            }

            do {
                let parsed = try decodeResult(data: data)
                AIParseDebugLogger.info(
                    "ResumeTailoringService: parsed candidate \(index + 1) successfully."
                )
                return parsed
            } catch {
                if (try? JSONSerialization.jsonObject(with: data)) != nil {
                    sawValidJSONCandidate = true
                }
                lastDecodeError = error
                AIParseDebugLogger.warning(
                    "ResumeTailoringService: candidate \(index + 1) failed to decode. Preview=\(AIParseDebugLogger.preview(candidate, maxLength: 300)). Error=\(decodeErrorDetails(error))"
                )
            }
        }

        if isLikelyTruncatedJSON(cleaned) {
            AIParseDebugLogger.error(
                "ResumeTailoringService: model output appears truncated (unterminated string/object/array)."
            )
            AIParseDebugLogger.infoFullText(
                "ResumeTailoringService: raw model output",
                text: rawResponse
            )
            throw AIServiceError.parsingError(truncatedResponseErrorMessage)
        }

        if sawValidJSONCandidate {
            AIParseDebugLogger.error(
                "ResumeTailoringService: model output looked like JSON but did not match expected schema. Last decode error=\(String(describing: lastDecodeError.map(decodeErrorDetails)))."
            )
            AIParseDebugLogger.infoFullText(
                "ResumeTailoringService: raw model output",
                text: rawResponse
            )
            throw AIServiceError.parsingError(schemaMismatchErrorMessage)
        }

        AIParseDebugLogger.error(
            "ResumeTailoringService: failed to find a parseable JSON payload in model output."
        )
        AIParseDebugLogger.infoFullText(
            "ResumeTailoringService: raw model output",
            text: rawResponse
        )

        throw AIServiceError.parsingError(invalidJSONErrorMessage)
    }

    private struct RawResult: Decodable {
        struct RawPatch: Decodable {
            let id: String?
            let path: String
            let operation: ResumePatch.Operation
            let beforeValue: JSONValue?
            let afterValue: JSONValue?
            let reason: String
            let evidencePaths: [String]?
            let risk: ResumePatch.Risk?

            private enum CodingKeys: String, CodingKey {
                case id
                case path
                case operation
                case op
                case beforeValue
                case before
                case afterValue
                case after
                case reason
                case evidencePaths
                case evidence_paths
                case risk
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                id = try container.decodeIfPresent(String.self, forKey: .id)
                path = try container.decode(String.self, forKey: .path)
                reason = try container.decode(String.self, forKey: .reason)

                if let rawOperation = try container.decodeIfPresent(String.self, forKey: .operation)
                    ?? (try container.decodeIfPresent(String.self, forKey: .op)) {
                    guard let normalized = ResumePatch.Operation(rawValue: rawOperation.lowercased()) else {
                        throw DecodingError.dataCorruptedError(
                            forKey: .operation,
                            in: container,
                            debugDescription: "Invalid patch operation: \(rawOperation)"
                        )
                    }
                    operation = normalized
                } else if let parsedOperation = try container.decodeIfPresent(ResumePatch.Operation.self, forKey: .operation) {
                    operation = parsedOperation
                } else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .operation,
                        in: container,
                        debugDescription: "Missing or invalid patch operation."
                    )
                }

                beforeValue = try container.decodeIfPresent(JSONValue.self, forKey: .beforeValue)
                    ?? container.decodeIfPresent(JSONValue.self, forKey: .before)
                afterValue = try container.decodeIfPresent(JSONValue.self, forKey: .afterValue)
                    ?? container.decodeIfPresent(JSONValue.self, forKey: .after)
                evidencePaths = try container.decodeIfPresent([String].self, forKey: .evidencePaths)
                    ?? container.decodeIfPresent([String].self, forKey: .evidence_paths)

                if let rawRisk = try container.decodeIfPresent(String.self, forKey: .risk) {
                    risk = ResumePatch.Risk(rawValue: rawRisk.lowercased())
                } else if let parsedRisk = try container.decodeIfPresent(ResumePatch.Risk.self, forKey: .risk) {
                    risk = parsedRisk
                } else {
                    risk = nil
                }
            }
        }

        let patches: [RawPatch]
        let sectionGaps: [String]?

        private enum CodingKeys: String, CodingKey {
            case patches
            case sectionGaps
            case section_gaps
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            patches = try container.decode([RawPatch].self, forKey: .patches)
            sectionGaps = try container.decodeIfPresent([String].self, forKey: .sectionGaps)
                ?? (try container.decodeIfPresent([String].self, forKey: .section_gaps))
        }
    }

    private static func decodeResult(data: Data) throws -> ResumeTailoringResult {
        let decoder = JSONDecoder()
        let raw: RawResult

        do {
            raw = try decoder.decode(RawResult.self, from: data)
        } catch {
            if let array = try? decoder.decode([RawResult].self, from: data), let first = array.first {
                raw = first
            } else {
                throw error
            }
        }

        let patches = raw.patches.map { item in
            ResumePatch(
                id: item.id.flatMap(UUID.init(uuidString:)) ?? UUID(),
                path: item.path,
                operation: item.operation,
                beforeValue: item.beforeValue,
                afterValue: item.afterValue,
                reason: item.reason,
                evidencePaths: item.evidencePaths ?? [],
                risk: item.risk ?? .medium
            )
        }

        return ResumeTailoringResult(
            patches: patches,
            sectionGaps: raw.sectionGaps ?? []
        )
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

        let withoutTrailingCommas = removeTrailingCommas(from: trimmed)
        appendIfNeeded(withoutTrailingCommas)

        if let extracted = extractJSONObject(from: trimmed) {
            appendIfNeeded(extracted)
        }

        if let extracted = extractJSONObject(from: withoutTrailingCommas) {
            appendIfNeeded(extracted)
        }

        if let repairedTruncated = repairPossiblyTruncatedJSONObject(from: trimmed) {
            appendIfNeeded(repairedTruncated)
        }

        if let repairedTruncated = repairPossiblyTruncatedJSONObject(from: withoutTrailingCommas) {
            appendIfNeeded(repairedTruncated)
        }

        return candidates
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

    private static func repairPossiblyTruncatedJSONObject(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let startIndex = trimmed.firstIndex(of: "{") else { return nil }

        var candidate = String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }

        var closingStack: [Character] = []
        var inString = false
        var escaped = false

        for character in candidate {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" {
                closingStack.append("}")
            } else if character == "}" {
                if closingStack.last == "}" {
                    _ = closingStack.popLast()
                }
            } else if character == "[" {
                closingStack.append("]")
            } else if character == "]" {
                if closingStack.last == "]" {
                    _ = closingStack.popLast()
                }
            }
        }

        if inString {
            if escaped {
                candidate.append("\\")
            }
            candidate.append("\"")
        }

        while let next = closingStack.popLast() {
            candidate.append(next)
        }

        return removeTrailingCommas(from: candidate)
    }

    private static func isLikelyTruncatedJSON(_ text: String) -> Bool {
        var objectDepth = 0
        var arrayDepth = 0
        var inString = false
        var escaped = false

        for character in text {
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            if character == "\"" {
                inString = true
                continue
            }

            if character == "{" {
                objectDepth += 1
            } else if character == "}", objectDepth > 0 {
                objectDepth -= 1
            } else if character == "[" {
                arrayDepth += 1
            } else if character == "]", arrayDepth > 0 {
                arrayDepth -= 1
            }
        }

        return inString || objectDepth > 0 || arrayDepth > 0
    }

    private static func decodeErrorDetails(_ error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }

        switch decodingError {
        case .keyNotFound(let key, let context):
            return "Missing key '\(key.stringValue)' at \(codingPath(context.codingPath)). \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            return "Type mismatch '\(type)' at \(codingPath(context.codingPath)). \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "Missing value '\(type)' at \(codingPath(context.codingPath)). \(context.debugDescription)"
        case .dataCorrupted(let context):
            return "Data corrupted at \(codingPath(context.codingPath)). \(context.debugDescription)"
        @unknown default:
            return error.localizedDescription
        }
    }

    private static func isRetryableTruncationError(_ error: Error) -> Bool {
        guard case .parsingError(let message) = error as? AIServiceError else {
            return false
        }
        return message.contains("appears truncated")
    }

    private static func codingPath(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "<root>" }
        return codingPath.map(\.stringValue).joined(separator: ".")
    }

    private static func removeTrailingCommas(from text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #",\s*([}\]])"#) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false

        for index in text[start...].indices {
            let ch = text[index]
            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                continue
            }

            if ch == "\"" {
                inString = true
                continue
            }

            if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
