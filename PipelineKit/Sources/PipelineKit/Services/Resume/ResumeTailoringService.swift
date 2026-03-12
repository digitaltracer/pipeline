import Foundation

public enum ResumeTailoringProgressEvent: Sendable, Equatable {
    case started
    case attemptStarted(attempt: Int, isRetry: Bool)
    case requestStarted(provider: AIProvider, model: String)
    case responseReceived(characters: Int, usage: AIUsageMetrics?)
    case parsingStarted
    case retryScheduled(reason: String)
    case completed(patchCount: Int, sectionGapCount: Int, usage: AIUsageMetrics?)
    case failed(message: String)
}

public enum ResumeTailoringService {
    private static let invalidJSONErrorMessage =
        "Resume tailoring response was not valid JSON. Retry Generate Suggestions."
    private static let schemaMismatchErrorMessage =
        "Resume tailoring response JSON did not match the expected schema. Retry Generate Suggestions."
    private static let truncatedResponseErrorMessage =
        "Resume tailoring response appears truncated before the JSON completed. Retry Generate Suggestions."
    private static let patchRevisionSchemaErrorMessage =
        "Patch revision response must return exactly one patch for the selected section."
    private static let tailoringMaxTokens = 25_000
    private static let patchRevisionMaxTokens = 8_000

    public static func generateSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        onProgress: (@Sendable (ResumeTailoringProgressEvent) -> Void)? = nil
    ) async throws -> ResumeTailoringResult {
        try await generateSuggestions(
            provider: provider,
            apiKey: apiKey,
            model: model,
            resumeJSON: resumeJSON,
            company: company,
            role: role,
            jobDescription: jobDescription,
            additionalInstructions: nil,
            onProgress: onProgress
        )
    }

    public static func generateATSFixSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        summary: String,
        missingKeywords: [String],
        criticalFindings: [String],
        warningFindings: [String],
        onProgress: (@Sendable (ResumeTailoringProgressEvent) -> Void)? = nil
    ) async throws -> ResumeTailoringResult {
        try await generateSuggestions(
            provider: provider,
            apiKey: apiKey,
            model: model,
            resumeJSON: resumeJSON,
            company: company,
            role: role,
            jobDescription: jobDescription,
            additionalInstructions: ResumeTailoringPrompts.atsFixInstructions(
                summary: summary,
                missingKeywords: missingKeywords,
                criticalFindings: criticalFindings,
                warningFindings: warningFindings
            ),
            onProgress: onProgress
        )
    }

    private static func generateSuggestions(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        additionalInstructions: String?,
        onProgress: (@Sendable (ResumeTailoringProgressEvent) -> Void)? = nil
    ) async throws -> ResumeTailoringResult {
        AIParseDebugLogger.info(
            "ResumeTailoringService: generating suggestions provider=\(provider.rawValue) model=\(model) resumeChars=\(resumeJSON.count) jobDescriptionChars=\(jobDescription.count)."
        )
        onProgress?(.started)

        let userPrompt = ResumeTailoringPrompts.userPrompt(
            resumeJSON: resumeJSON,
            company: company,
            role: role,
            jobDescription: jobDescription,
            additionalInstructions: additionalInstructions
        )

        let attemptPrompts = [
            ResumeTailoringPrompts.systemPrompt,
            ResumeTailoringPrompts.compactRetrySystemPrompt
        ]

        for attemptIndex in attemptPrompts.indices {
            let systemPrompt = attemptPrompts[attemptIndex]
            let isRetryAttempt = attemptIndex > 0
            onProgress?(.attemptStarted(attempt: attemptIndex + 1, isRetry: isRetryAttempt))

            if isRetryAttempt {
                AIParseDebugLogger.warning(
                    "ResumeTailoringService: retrying with compact prompt after truncated response."
                )
                onProgress?(.retryScheduled(reason: "Previous response appeared truncated. Retrying with compact prompt."))
            }

            onProgress?(.requestStarted(provider: provider, model: model))
            let response: AICompletionResponse
            do {
                response = try await AICompletionClient.completeWithUsage(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    systemPrompt: systemPrompt,
                    userPrompt: userPrompt,
                    maxTokens: tailoringMaxTokens,
                    temperature: isRetryAttempt ? 0.2 : 0.3
                )
            } catch {
                onProgress?(.failed(message: error.localizedDescription))
                throw error
            }
            onProgress?(.responseReceived(characters: response.text.count, usage: response.usage))
            onProgress?(.parsingStarted)

            do {
                let parsed = try parseResult(from: response.text)
                let result = ResumeTailoringResult(
                    patches: parsed.patches,
                    sectionGaps: parsed.sectionGaps,
                    usage: response.usage
                )
                onProgress?(
                    .completed(
                        patchCount: result.patches.count,
                        sectionGapCount: result.sectionGaps.count,
                        usage: result.usage
                    )
                )
                return result
            } catch {
                guard isRetryableTruncationError(error), !isRetryAttempt else {
                    onProgress?(.failed(message: error.localizedDescription))
                    throw error
                }
                onProgress?(.retryScheduled(reason: "Parser detected truncated JSON response."))
            }
        }

        onProgress?(.failed(message: truncatedResponseErrorMessage))
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
                    "ResumeTailoringService: candidate \(index + 1) failed to decode. candidateChars=\(candidate.count) error=\(decodeErrorDetails(error))."
                )
            }
        }

        if isLikelyTruncatedJSON(cleaned) {
            AIParseDebugLogger.error(
                "ResumeTailoringService: model output appears truncated (unterminated string/object/array)."
            )
            throw AIServiceError.parsingError(truncatedResponseErrorMessage)
        }

        if sawValidJSONCandidate {
            AIParseDebugLogger.error(
                "ResumeTailoringService: model output looked like JSON but did not match expected schema. Last decode error=\(String(describing: lastDecodeError.map(decodeErrorDetails)))."
            )
            throw AIServiceError.parsingError(schemaMismatchErrorMessage)
        }

        AIParseDebugLogger.error(
            "ResumeTailoringService: failed to find a parseable JSON payload in model output."
        )

        throw AIServiceError.parsingError(invalidJSONErrorMessage)
    }

    public static func revisePatch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        resumeJSON: String,
        company: String,
        role: String,
        jobDescription: String,
        selectedPatch: ResumePatch,
        userInstruction: String
    ) async throws -> ResumeTailoringResult {
        let trimmedInstruction = userInstruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            throw AIServiceError.parsingError("Custom instruction cannot be empty.")
        }

        AIParseDebugLogger.info(
            "ResumeTailoringService: revising patch provider=\(provider.rawValue) model=\(model) path=\(selectedPatch.path) instructionChars=\(trimmedInstruction.count)."
        )

        let userPrompt = ResumeTailoringPrompts.patchRevisionUserPrompt(
            resumeJSON: resumeJSON,
            company: company,
            role: role,
            jobDescription: jobDescription,
            selectedPatch: selectedPatch,
            userInstruction: trimmedInstruction
        )

        let attemptPrompts = [
            ResumeTailoringPrompts.patchRevisionSystemPrompt,
            ResumeTailoringPrompts.patchRevisionCompactRetrySystemPrompt
        ]

        for attemptIndex in attemptPrompts.indices {
            let isRetryAttempt = attemptIndex > 0

            if isRetryAttempt {
                AIParseDebugLogger.warning(
                    "ResumeTailoringService: retrying patch revision with compact prompt after truncated response."
                )
            }

            let response = try await AICompletionClient.completeWithUsage(
                provider: provider,
                apiKey: apiKey,
                model: model,
                systemPrompt: attemptPrompts[attemptIndex],
                userPrompt: userPrompt,
                maxTokens: patchRevisionMaxTokens,
                temperature: isRetryAttempt ? 0.15 : 0.2
            )

            do {
                let parsed = try parseResult(from: response.text)
                let revisedPatch = try validateRevisedPatch(
                    parsed,
                    expectedPath: selectedPatch.path
                )
                return ResumeTailoringResult(
                    patches: [revisedPatch],
                    sectionGaps: [],
                    usage: response.usage
                )
            } catch {
                guard isRetryableTruncationError(error), !isRetryAttempt else {
                    throw error
                }
            }
        }

        throw AIServiceError.parsingError(truncatedResponseErrorMessage)
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

    private static func validateRevisedPatch(
        _ result: ResumeTailoringResult,
        expectedPath: String
    ) throws -> ResumePatch {
        guard result.patches.count == 1 else {
            throw AIServiceError.parsingError(patchRevisionSchemaErrorMessage)
        }

        let patch = result.patches[0]
        guard patch.path == expectedPath else {
            throw AIServiceError.parsingError(
                "\(patchRevisionSchemaErrorMessage) Expected path \(expectedPath), got \(patch.path)."
            )
        }

        return patch
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
