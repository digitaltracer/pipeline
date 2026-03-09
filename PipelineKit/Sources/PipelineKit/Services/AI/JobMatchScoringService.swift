import CryptoKit
import Foundation

public struct JobMatchAIAnalysis: Sendable, Equatable {
    public let skillsScore: Int
    public let experienceScore: Int
    public let matchedSkills: [String]
    public let missingSkills: [String]
    public let summary: String
    public let gapAnalysis: String
    public let usage: AIUsageMetrics?

    public init(
        skillsScore: Int,
        experienceScore: Int,
        matchedSkills: [String],
        missingSkills: [String],
        summary: String,
        gapAnalysis: String,
        usage: AIUsageMetrics? = nil
    ) {
        self.skillsScore = skillsScore
        self.experienceScore = experienceScore
        self.matchedSkills = matchedSkills
        self.missingSkills = missingSkills
        self.summary = summary
        self.gapAnalysis = gapAnalysis
        self.usage = usage
    }
}

public struct JobMatchAssessmentDraft: Sendable, Equatable {
    public let overallScore: Int?
    public let skillsScore: Int?
    public let experienceScore: Int?
    public let salaryScore: Int?
    public let locationScore: Int?
    public let matchedSkills: [String]
    public let missingSkills: [String]
    public let summary: String?
    public let gapAnalysis: String?
    public let status: JobMatchAssessmentStatus
    public let blockedReason: JobMatchBlockedReason?
    public let lastErrorMessage: String?
    public let jobDescriptionHash: String?
    public let preferencesFingerprint: String
    public let scoringVersion: String
    public let scoredAt: Date
    public let usage: AIUsageMetrics?

    public init(
        overallScore: Int?,
        skillsScore: Int?,
        experienceScore: Int?,
        salaryScore: Int?,
        locationScore: Int?,
        matchedSkills: [String],
        missingSkills: [String],
        summary: String?,
        gapAnalysis: String?,
        status: JobMatchAssessmentStatus,
        blockedReason: JobMatchBlockedReason?,
        lastErrorMessage: String?,
        jobDescriptionHash: String?,
        preferencesFingerprint: String,
        scoringVersion: String,
        scoredAt: Date,
        usage: AIUsageMetrics?
    ) {
        self.overallScore = overallScore
        self.skillsScore = skillsScore
        self.experienceScore = experienceScore
        self.salaryScore = salaryScore
        self.locationScore = locationScore
        self.matchedSkills = matchedSkills
        self.missingSkills = missingSkills
        self.summary = summary
        self.gapAnalysis = gapAnalysis
        self.status = status
        self.blockedReason = blockedReason
        self.lastErrorMessage = lastErrorMessage
        self.jobDescriptionHash = jobDescriptionHash
        self.preferencesFingerprint = preferencesFingerprint
        self.scoringVersion = scoringVersion
        self.scoredAt = scoredAt
        self.usage = usage
    }
}

public enum JobMatchScoringService {
    public static let scoringVersion = "job-match-v1"
    private static let responseMaxTokens = 20_000

    public static func score(
        provider: AIProvider,
        apiKey: String,
        model: String,
        application: JobApplication,
        resumeJSON: String,
        preferences: JobMatchPreferences,
        exchangeRateService: ExchangeRateProviding = ExchangeRateService.shared,
        referenceDate: Date = Date()
    ) async throws -> JobMatchAssessmentDraft {
        let trimmedResume = resumeJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedResume.isEmpty else {
            return blockedDraft(
                reason: .missingMasterResume,
                application: application,
                preferences: preferences,
                referenceDate: referenceDate
            )
        }

        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else {
            return blockedDraft(
                reason: .missingJobDescription,
                application: application,
                preferences: preferences,
                referenceDate: referenceDate
            )
        }

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: AIServicePrompts.jobMatchScoringPrompt,
            userPrompt: AIServicePrompts.jobMatchScoringUserPrompt(
                resumeJSON: String(trimmedResume.prefix(16_000)),
                jobDescription: String(description.prefix(8_000))
            ),
            maxTokens: responseMaxTokens,
            temperature: 0.2
        )

        let analysis = try parseAIAnalysis(from: response.text, usage: response.usage)
        let salaryScore = await computeSalaryScore(
            application: application,
            preferences: preferences,
            exchangeRateService: exchangeRateService,
            referenceDate: referenceDate
        )
        let locationScore = computeLocationScore(application: application, preferences: preferences)
        let overallScore = computeOverallScore(
            skillsScore: analysis.skillsScore,
            experienceScore: analysis.experienceScore,
            salaryScore: salaryScore,
            locationScore: locationScore
        )

        return JobMatchAssessmentDraft(
            overallScore: overallScore,
            skillsScore: analysis.skillsScore,
            experienceScore: analysis.experienceScore,
            salaryScore: salaryScore,
            locationScore: locationScore,
            matchedSkills: analysis.matchedSkills,
            missingSkills: analysis.missingSkills,
            summary: analysis.summary,
            gapAnalysis: analysis.gapAnalysis,
            status: .ready,
            blockedReason: nil,
            lastErrorMessage: nil,
            jobDescriptionHash: jobDescriptionHash(for: application),
            preferencesFingerprint: preferences.fingerprint,
            scoringVersion: scoringVersion,
            scoredAt: referenceDate,
            usage: analysis.usage
        )
    }

    public static func blockedDraft(
        reason: JobMatchBlockedReason,
        application: JobApplication,
        preferences: JobMatchPreferences,
        referenceDate: Date = Date()
    ) -> JobMatchAssessmentDraft {
        JobMatchAssessmentDraft(
            overallScore: nil,
            skillsScore: nil,
            experienceScore: nil,
            salaryScore: nil,
            locationScore: nil,
            matchedSkills: [],
            missingSkills: [],
            summary: nil,
            gapAnalysis: nil,
            status: .blocked,
            blockedReason: reason,
            lastErrorMessage: nil,
            jobDescriptionHash: jobDescriptionHash(for: application),
            preferencesFingerprint: preferences.fingerprint,
            scoringVersion: scoringVersion,
            scoredAt: referenceDate,
            usage: nil
        )
    }

    public static func jobDescriptionHash(for application: JobApplication) -> String? {
        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(description.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isStale(
        _ assessment: JobMatchAssessment,
        application: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Bool {
        if assessment.scoringVersion != scoringVersion {
            return true
        }

        if assessment.resumeRevisionID != currentResumeRevisionID {
            return true
        }

        if assessment.preferencesFingerprint != preferences.fingerprint {
            return true
        }

        return assessment.jobDescriptionHash != jobDescriptionHash(for: application)
    }

    public static func shouldAutoRefresh(
        _ assessment: JobMatchAssessment,
        application: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Bool {
        if assessment.status == .blocked {
            switch assessment.blockedReason {
            case .missingJobDescription:
                return jobDescriptionHash(for: application) != nil
            case .missingMasterResume:
                return currentResumeRevisionID != nil
            case .missingPreferences:
                return preferences.hasSalaryPreference || preferences.hasLocationPreference
            case .none:
                return true
            }
        }

        guard isStale(assessment, application: application, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences) else {
            return false
        }

        let resumeMatches = assessment.resumeRevisionID == currentResumeRevisionID
        let prefsMatch = assessment.preferencesFingerprint == preferences.fingerprint
        let descriptionChanged = assessment.jobDescriptionHash != jobDescriptionHash(for: application)
        return resumeMatches && prefsMatch && descriptionChanged
    }

    static func parseAIAnalysis(from rawJSON: String, usage: AIUsageMetrics?) throws -> JobMatchAIAnalysis {
        let cleaned = stripMarkdownFences(from: rawJSON)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            if let extracted = extractJSONObject(from: cleaned),
               let extractedData = extracted.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: extractedData) as? [String: Any] {
                return try buildAIAnalysis(from: json, usage: usage)
            }
            throw AIServiceError.parsingError("Job match scoring response was not valid JSON.")
        }

        return try buildAIAnalysis(from: json, usage: usage)
    }

    static func computeOverallScore(
        skillsScore: Int?,
        experienceScore: Int?,
        salaryScore: Int?,
        locationScore: Int?
    ) -> Int? {
        let weightedScores: [(score: Int?, weight: Double)] = [
            (skillsScore, 0.50),
            (experienceScore, 0.20),
            (salaryScore, 0.15),
            (locationScore, 0.15)
        ]

        let available = weightedScores.compactMap { item -> (Double, Double)? in
            guard let score = item.score else { return nil }
            return (Double(score), item.weight)
        }

        guard !available.isEmpty else { return nil }
        let totalWeight = available.reduce(0) { $0 + $1.1 }
        let weightedTotal = available.reduce(0.0) { $0 + ($1.0 * ($1.1 / totalWeight)) }
        return clampScore(Int(weightedTotal.rounded()))
    }

    static func computeLocationScore(
        application: JobApplication,
        preferences: JobMatchPreferences
    ) -> Int? {
        let allowedModes = Set(preferences.normalizedAllowedWorkModes)
        guard !allowedModes.isEmpty else { return nil }

        let normalizedLocation = application.location.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedLocation.isEmpty else { return nil }

        let locationLower = normalizedLocation.lowercased()
        let inferredModes = inferWorkModes(from: locationLower)
        let preferredLocations = preferences.normalizedPreferredLocations.map { $0.lowercased() }

        if inferredModes.contains(.remote) {
            return allowedModes.contains(.remote) ? 100 : 0
        }

        if inferredModes.contains(.hybrid) {
            guard allowedModes.contains(.hybrid) else { return 0 }
            return preferredLocations.isEmpty || preferredLocations.contains(where: { locationLower.contains($0) }) ? 100 : 0
        }

        if inferredModes.contains(.onSite) {
            guard allowedModes.contains(.onSite) else { return 0 }
            return preferredLocations.isEmpty || preferredLocations.contains(where: { locationLower.contains($0) }) ? 100 : 0
        }

        if preferredLocations.isEmpty {
            return nil
        }

        return preferredLocations.contains(where: { locationLower.contains($0) }) ? 100 : nil
    }

    static func computeSalaryScore(
        postedMaximumCompensationInPreferenceCurrency: Double?,
        targetMinimumCompensationInPreferenceCurrency: Double?
    ) -> Int? {
        guard let postedMaximum = postedMaximumCompensationInPreferenceCurrency,
              let targetMinimum = targetMinimumCompensationInPreferenceCurrency,
              targetMinimum > 0 else {
            return nil
        }

        if postedMaximum >= targetMinimum {
            return 100
        }

        let ratio = max(0, min(1, postedMaximum / targetMinimum))
        return clampScore(Int((ratio * 100).rounded()))
    }

    static func inferWorkModes(from normalizedLocation: String) -> Set<JobMatchWorkMode> {
        var result: Set<JobMatchWorkMode> = []
        if normalizedLocation.contains("remote") {
            result.insert(.remote)
        }
        if normalizedLocation.contains("hybrid") {
            result.insert(.hybrid)
        }
        if normalizedLocation.contains("on-site") || normalizedLocation.contains("onsite") {
            result.insert(.onSite)
        }
        return result
    }

    private static func computeSalaryScore(
        application: JobApplication,
        preferences: JobMatchPreferences,
        exchangeRateService: ExchangeRateProviding,
        referenceDate: Date
    ) async -> Int? {
        let targetMinimum = application.expectedSalaryMin ?? preferences.preferredSalaryMin
        let targetCurrency = application.expectedSalaryMin != nil ? application.currency : preferences.preferredCurrency
        guard let targetMinimum else { return nil }

        let postedMaximum = application.salaryMax ?? application.salaryMin
        guard let postedMaximum else { return nil }

        let postedValue: Double
        if application.currency == preferences.preferredCurrency {
            postedValue = Double(postedMaximum)
        } else if let converted = await exchangeRateService.convert(
            amount: postedMaximum,
            from: application.currency,
            to: preferences.preferredCurrency,
            on: referenceDate
        ) {
            postedValue = converted.amount
        } else {
            return nil
        }

        let targetValue: Double
        if targetCurrency == preferences.preferredCurrency {
            targetValue = Double(targetMinimum)
        } else if let converted = await exchangeRateService.convert(
            amount: targetMinimum,
            from: targetCurrency,
            to: preferences.preferredCurrency,
            on: referenceDate
        ) {
            targetValue = converted.amount
        } else {
            return nil
        }

        return computeSalaryScore(
            postedMaximumCompensationInPreferenceCurrency: postedValue,
            targetMinimumCompensationInPreferenceCurrency: targetValue
        )
    }

    private static func buildAIAnalysis(
        from json: [String: Any],
        usage: AIUsageMetrics?
    ) throws -> JobMatchAIAnalysis {
        let skillsScore = clampScore(intValue(json["skillsScore"] ?? json["skills_score"]))
        let experienceScore = clampScore(intValue(json["experienceScore"] ?? json["experience_score"]))
        let matchedSkills = stringArrayValue(json["matchedSkills"] ?? json["matched_skills"])
        let missingSkills = stringArrayValue(json["missingSkills"] ?? json["missing_skills"])
        let summary = stringValue(json["summary"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let gapAnalysis = stringValue(json["gapAnalysis"] ?? json["gap_analysis"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard let skillsScore, let experienceScore, !summary.isEmpty else {
            throw AIServiceError.parsingError("Job match scoring response did not include the expected schema.")
        }

        return JobMatchAIAnalysis(
            skillsScore: skillsScore,
            experienceScore: experienceScore,
            matchedSkills: matchedSkills,
            missingSkills: missingSkills,
            summary: summary,
            gapAnalysis: gapAnalysis,
            usage: usage
        )
    }

    private static func stringArrayValue(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { stringValue($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int {
            return int
        }
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let string = value as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func clampScore(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return max(0, min(100, value))
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

    private static func extractJSONObject(from text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escaped = false

        for index in text[start...].indices {
            let character = text[index]
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
                depth += 1
            } else if character == "}" {
                depth -= 1
                if depth == 0 {
                    return String(text[start...index])
                }
            }
        }

        return nil
    }
}
