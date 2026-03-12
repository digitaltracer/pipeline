import CryptoKit
import Foundation

public struct ATSCompatibilityAssessmentDraft: Sendable, Equatable {
    public let overallScore: Int?
    public let keywordScore: Int?
    public let sectionScore: Int?
    public let contactScore: Int?
    public let formatScore: Int?
    public let summary: String?
    public let matchedKeywords: [String]
    public let missingKeywords: [String]
    public let criticalFindings: [String]
    public let warningFindings: [String]
    public let status: ATSAssessmentStatus
    public let blockedReason: ATSBlockedReason?
    public let resumeSourceKind: ATSResumeSourceKind?
    public let resumeSourceSnapshotID: UUID?
    public let resumeSourceRevisionID: UUID?
    public let resumeSourceFingerprint: String?
    public let lastErrorMessage: String?
    public let jobDescriptionHash: String?
    public let scoringVersion: String
    public let scoredAt: Date

    public init(
        overallScore: Int?,
        keywordScore: Int?,
        sectionScore: Int?,
        contactScore: Int?,
        formatScore: Int?,
        summary: String?,
        matchedKeywords: [String],
        missingKeywords: [String],
        criticalFindings: [String],
        warningFindings: [String],
        status: ATSAssessmentStatus,
        blockedReason: ATSBlockedReason?,
        resumeSourceKind: ATSResumeSourceKind?,
        resumeSourceSnapshotID: UUID?,
        resumeSourceRevisionID: UUID?,
        resumeSourceFingerprint: String?,
        lastErrorMessage: String?,
        jobDescriptionHash: String?,
        scoringVersion: String,
        scoredAt: Date
    ) {
        self.overallScore = overallScore
        self.keywordScore = keywordScore
        self.sectionScore = sectionScore
        self.contactScore = contactScore
        self.formatScore = formatScore
        self.summary = summary
        self.matchedKeywords = matchedKeywords
        self.missingKeywords = missingKeywords
        self.criticalFindings = criticalFindings
        self.warningFindings = warningFindings
        self.status = status
        self.blockedReason = blockedReason
        self.resumeSourceKind = resumeSourceKind
        self.resumeSourceSnapshotID = resumeSourceSnapshotID
        self.resumeSourceRevisionID = resumeSourceRevisionID
        self.resumeSourceFingerprint = resumeSourceFingerprint
        self.lastErrorMessage = lastErrorMessage
        self.jobDescriptionHash = jobDescriptionHash
        self.scoringVersion = scoringVersion
        self.scoredAt = scoredAt
    }
}

public enum ATSCompatibilityScoringService {
    public static let scoringVersion = "ats-compat-v1"

    private static let keywordWeight = 0.55
    private static let sectionWeight = 0.20
    private static let contactWeight = 0.15
    private static let formatWeight = 0.10

    private struct WeightedKeyword {
        let display: String
        let normalized: String
        let specialTerm: SpecialTerm?
        var weight: Double
        var occurrences: Int
        var isTitleTerm: Bool
    }

    private struct SpecialTerm {
        let display: String
        let aliases: [String]
        let usesWordBoundaries: Bool
    }

    private struct KeywordAnalysis {
        let score: Int
        let matched: [String]
        let missing: [String]
        let criticalFindings: [String]
        let warningFindings: [String]
        let totalWeightedTerms: Int
    }

    private struct SectionAnalysis {
        let score: Int
        let warningFindings: [String]
    }

    private struct ContactAnalysis {
        let score: Int
        let warningFindings: [String]
        let criticalFindings: [String]
    }

    private struct FormatAnalysis {
        let score: Int
        let warningFindings: [String]
        let criticalFindings: [String]
    }

    private static let specialTerms: [SpecialTerm] = [
        SpecialTerm(display: "CI/CD", aliases: ["ci/cd", "ci cd", "continuous integration", "continuous delivery"], usesWordBoundaries: false),
        SpecialTerm(display: "gRPC", aliases: ["grpc"], usesWordBoundaries: true),
        SpecialTerm(display: ".NET", aliases: [".net", "dotnet"], usesWordBoundaries: false),
        SpecialTerm(display: "C++", aliases: ["c++"], usesWordBoundaries: false),
        SpecialTerm(display: "Kubernetes", aliases: ["kubernetes", "k8s"], usesWordBoundaries: true),
        SpecialTerm(display: "DataDog", aliases: ["datadog", "data dog"], usesWordBoundaries: true),
        SpecialTerm(display: "AWS", aliases: ["aws", "amazon web services"], usesWordBoundaries: true),
        SpecialTerm(display: "GCP", aliases: ["gcp", "google cloud"], usesWordBoundaries: true),
        SpecialTerm(display: "Azure", aliases: ["azure"], usesWordBoundaries: true),
        SpecialTerm(display: "REST API", aliases: ["rest api", "restful api"], usesWordBoundaries: false),
        SpecialTerm(display: "GraphQL", aliases: ["graphql"], usesWordBoundaries: true),
        SpecialTerm(display: "Machine Learning", aliases: ["machine learning", "ml"], usesWordBoundaries: false),
        SpecialTerm(display: "System Design", aliases: ["system design"], usesWordBoundaries: false),
        SpecialTerm(display: "Distributed Systems", aliases: ["distributed systems"], usesWordBoundaries: false),
        SpecialTerm(display: "Microservices", aliases: ["microservices", "micro services"], usesWordBoundaries: false)
    ]

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "from", "this", "have", "will", "you",
        "your", "our", "their", "about", "into", "role", "team", "work", "works",
        "working", "using", "build", "built", "develop", "developed", "developer",
        "engineer", "engineering", "experience", "years", "year", "requirements",
        "required", "preferred", "skills", "skill", "ability", "abilities", "plus",
        "nice", "must", "should", "can", "job", "description", "candidate", "across",
        "through", "within", "strong", "excellent", "knowledge", "understanding",
        "designing", "building", "teams", "products", "product"
    ]

    public static func prepareDraft(
        application: JobApplication,
        resumeSource: ResumeSourceSelection?,
        referenceDate: Date = Date()
    ) throws -> ATSCompatibilityAssessmentDraft {
        guard let resumeSource else {
            return blockedDraft(
                reason: .missingResumeSource,
                application: application,
                resumeSource: nil,
                referenceDate: referenceDate
            )
        }

        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else {
            return blockedDraft(
                reason: .missingJobDescription,
                application: application,
                resumeSource: resumeSource,
                referenceDate: referenceDate
            )
        }

        let resume = try ResumeSchemaValidator.validate(jsonText: resumeSource.rawJSON).schema

        let keywordAnalysis = analyzeKeywords(
            role: application.role,
            jobDescription: description,
            resume: resume
        )
        let sectionAnalysis = analyzeSections(resume: resume)
        let contactAnalysis = analyzeContact(resume: resume)
        let formatAnalysis = analyzeFormat(resume: resume)

        let overallScore = Int(
            (
                Double(keywordAnalysis.score) * keywordWeight
                + Double(sectionAnalysis.score) * sectionWeight
                + Double(contactAnalysis.score) * contactWeight
                + Double(formatAnalysis.score) * formatWeight
            )
            .rounded()
        )

        let summary = makeSummary(
            keywordAnalysis: keywordAnalysis,
            sectionAnalysis: sectionAnalysis,
            contactAnalysis: contactAnalysis,
            formatAnalysis: formatAnalysis
        )

        return ATSCompatibilityAssessmentDraft(
            overallScore: overallScore,
            keywordScore: keywordAnalysis.score,
            sectionScore: sectionAnalysis.score,
            contactScore: contactAnalysis.score,
            formatScore: formatAnalysis.score,
            summary: summary,
            matchedKeywords: keywordAnalysis.matched,
            missingKeywords: keywordAnalysis.missing,
            criticalFindings: deduplicated(keywordAnalysis.criticalFindings + contactAnalysis.criticalFindings + formatAnalysis.criticalFindings),
            warningFindings: deduplicated(keywordAnalysis.warningFindings + sectionAnalysis.warningFindings + contactAnalysis.warningFindings + formatAnalysis.warningFindings),
            status: .ready,
            blockedReason: nil,
            resumeSourceKind: atsResumeSourceKind(for: resumeSource.kind),
            resumeSourceSnapshotID: resumeSource.snapshotID,
            resumeSourceRevisionID: resumeSource.masterRevisionID,
            resumeSourceFingerprint: resumeSourceFingerprint(for: resumeSource),
            lastErrorMessage: nil,
            jobDescriptionHash: jobDescriptionHash(for: application),
            scoringVersion: scoringVersion,
            scoredAt: referenceDate
        )
    }

    public static func blockedDraft(
        reason: ATSBlockedReason,
        application: JobApplication,
        resumeSource: ResumeSourceSelection?,
        referenceDate: Date = Date()
    ) -> ATSCompatibilityAssessmentDraft {
        ATSCompatibilityAssessmentDraft(
            overallScore: nil,
            keywordScore: nil,
            sectionScore: nil,
            contactScore: nil,
            formatScore: nil,
            summary: nil,
            matchedKeywords: [],
            missingKeywords: [],
            criticalFindings: [],
            warningFindings: [],
            status: .blocked,
            blockedReason: reason,
            resumeSourceKind: resumeSource.map { atsResumeSourceKind(for: $0.kind) },
            resumeSourceSnapshotID: resumeSource?.snapshotID,
            resumeSourceRevisionID: resumeSource?.masterRevisionID,
            resumeSourceFingerprint: resumeSource.flatMap(resumeSourceFingerprint(for:)),
            lastErrorMessage: nil,
            jobDescriptionHash: jobDescriptionHash(for: application),
            scoringVersion: scoringVersion,
            scoredAt: referenceDate
        )
    }

    public static func jobDescriptionHash(for application: JobApplication) -> String? {
        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else { return nil }
        let digest = SHA256.hash(data: Data(description.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func resumeSourceFingerprint(for resumeSource: ResumeSourceSelection?) -> String? {
        guard let rawJSON = resumeSource?.rawJSON else { return nil }
        let digest = SHA256.hash(data: Data(rawJSON.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func isStale(
        _ assessment: ATSCompatibilityAssessment,
        application: JobApplication,
        resumeSource: ResumeSourceSelection?
    ) -> Bool {
        if assessment.scoringVersion != scoringVersion {
            return true
        }

        if assessment.jobDescriptionHash != jobDescriptionHash(for: application) {
            return true
        }

        let expectedKind = resumeSource.map { atsResumeSourceKind(for: $0.kind).rawValue }
        if assessment.resumeSourceKindRawValue != expectedKind {
            return true
        }

        if assessment.resumeSourceSnapshotID != resumeSource?.snapshotID {
            return true
        }

        if assessment.resumeSourceRevisionID != resumeSource?.masterRevisionID {
            return true
        }

        return assessment.resumeSourceFingerprint != resumeSourceFingerprint(for: resumeSource)
    }

    public static func shouldAutoRefresh(
        _ assessment: ATSCompatibilityAssessment,
        application: JobApplication,
        resumeSource: ResumeSourceSelection?
    ) -> Bool {
        if assessment.status == .blocked {
            switch assessment.blockedReason {
            case .missingJobDescription:
                return jobDescriptionHash(for: application) != nil
            case .missingResumeSource:
                return resumeSource != nil
            case .none:
                return true
            }
        }

        if assessment.status == .failed {
            return isStale(assessment, application: application, resumeSource: resumeSource)
        }

        return isStale(assessment, application: application, resumeSource: resumeSource)
    }

    private static func analyzeKeywords(
        role: String,
        jobDescription: String,
        resume: ResumeSchema
    ) -> KeywordAnalysis {
        let title = role.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidates: [String: WeightedKeyword] = [:]

        accumulateSpecialTerms(in: title, weightMultiplier: 3.0, isTitle: true, into: &candidates)
        accumulateSpecialTerms(in: jobDescription, weightMultiplier: 1.8, isTitle: false, into: &candidates)
        accumulateTokens(in: title, weightMultiplier: 3.0, into: &candidates)
        accumulateTokens(in: jobDescription, weightMultiplier: 1.0, into: &candidates)
        accumulatePhrases(in: title, weightMultiplier: 2.4, into: &candidates)
        accumulatePhrases(in: jobDescription, weightMultiplier: 1.1, into: &candidates)

        let selected = candidates.values
            .sorted { lhs, rhs in
                if lhs.weight == rhs.weight {
                    if lhs.occurrences == rhs.occurrences {
                        return lhs.display.count > rhs.display.count
                    }
                    return lhs.occurrences > rhs.occurrences
                }
                return lhs.weight > rhs.weight
            }
            .reduce(into: [WeightedKeyword]()) { result, candidate in
                guard result.count < 12 else { return }
                if result.contains(where: { $0.normalized == candidate.normalized }) {
                    return
                }
                result.append(candidate)
            }

        guard !selected.isEmpty else {
            return KeywordAnalysis(
                score: 0,
                matched: [],
                missing: [],
                criticalFindings: [],
                warningFindings: ["No ATS keywords could be extracted from the job description."],
                totalWeightedTerms: 0
            )
        }

        let resumeRawText = resumeSearchText(from: resume)
        let resumeNormalizedText = normalizedSearchText(from: resumeRawText)
        var matched: [String] = []
        var missing: [String] = []
        var matchedWeight = 0.0
        var totalWeight = 0.0
        var criticalFindings: [String] = []
        var warningFindings: [String] = []

        for candidate in selected {
            totalWeight += candidate.weight
            if keyword(candidate, appearsIn: resumeRawText, normalizedText: resumeNormalizedText) {
                matched.append(candidate.display)
                matchedWeight += candidate.weight
            } else {
                missing.append(candidate.display)
                if candidate.isTitleTerm || candidate.occurrences >= 2 {
                    criticalFindings.append("\(candidate.display) is emphasized in the JD but absent from the resume.")
                }
            }
        }

        let score = totalWeight > 0
            ? Int(((matchedWeight / totalWeight) * 100).rounded())
            : 0

        if !missing.isEmpty {
            warningFindings.append("\(missing.count) of \(selected.count) weighted JD terms are missing from the resume.")
        }

        return KeywordAnalysis(
            score: score,
            matched: matched,
            missing: missing,
            criticalFindings: deduplicated(criticalFindings),
            warningFindings: deduplicated(warningFindings),
            totalWeightedTerms: selected.count
        )
    }

    private static func analyzeSections(resume: ResumeSchema) -> SectionAnalysis {
        var presentCount = 0
        var warningFindings: [String] = []

        if !resume.experience.isEmpty {
            presentCount += 1
        } else {
            warningFindings.append("Experience section is missing or empty.")
        }

        if !resume.education.isEmpty {
            presentCount += 1
        } else {
            warningFindings.append("Education section is missing or empty.")
        }

        if !resume.skills.isEmpty {
            presentCount += 1
        } else {
            warningFindings.append("Skills section is missing or empty.")
        }

        let score = Int((Double(presentCount) / 3.0 * 100.0).rounded())
        return SectionAnalysis(score: score, warningFindings: warningFindings)
    }

    private static func analyzeContact(resume: ResumeSchema) -> ContactAnalysis {
        var score = 100
        var warningFindings: [String] = []
        var criticalFindings: [String] = []

        if !isValidEmail(resume.contact.email) {
            score -= 50
            criticalFindings.append("Email is missing or not parseable.")
        }

        if !isValidPhone(resume.contact.phone) {
            score -= 40
            criticalFindings.append("Phone number is missing or not parseable.")
        }

        if !resume.contact.linkedin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isLikelyProfileURL(resume.contact.linkedin) {
            score -= 5
            warningFindings.append("LinkedIn URL looks malformed.")
        }

        if !resume.contact.github.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !isLikelyProfileURL(resume.contact.github) {
            score -= 5
            warningFindings.append("GitHub URL looks malformed.")
        }

        return ContactAnalysis(
            score: max(0, score),
            warningFindings: warningFindings,
            criticalFindings: criticalFindings
        )
    }

    private static func analyzeFormat(resume: ResumeSchema) -> FormatAnalysis {
        var score = 100
        var warningFindings: [String] = []
        var criticalFindings: [String] = []

        if let summary = resume.summary,
           wordCount(summary) > 80 {
            score -= 12
            warningFindings.append("Summary is longer than 80 words.")
        }

        if resume.experience.contains(where: { $0.company.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            score -= 20
            criticalFindings.append("At least one experience entry is missing a company name.")
        }

        if resume.experience.contains(where: { $0.dates.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            score -= 15
            warningFindings.append("At least one experience entry is missing dates.")
        }

        if resume.education.contains(where: { $0.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            score -= 10
            warningFindings.append("At least one education entry is missing dates.")
        }

        if resume.projects.contains(where: { $0.date.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            score -= 10
            warningFindings.append("At least one project entry is missing dates.")
        }

        let longBulletCount = longBulletCount(in: resume)
        if longBulletCount > 0 {
            score -= min(20, longBulletCount * 4)
            warningFindings.append("\(longBulletCount) bullet\(longBulletCount == 1 ? "" : "s") exceed 32 words.")
        }

        let denseSkillCategories = resume.skills.filter { $0.value.count >= 8 }
        if !denseSkillCategories.isEmpty {
            score -= 8
            warningFindings.append("Skills section is dense and will render as comma-separated lines in the exported PDF.")
        }

        if resume.projects.contains(where: { project in
            guard let url = project.url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            return !isLikelyProfileURL(url)
        }) {
            score -= 5
            warningFindings.append("At least one project URL looks malformed.")
        }

        return FormatAnalysis(
            score: max(0, score),
            warningFindings: deduplicated(warningFindings),
            criticalFindings: deduplicated(criticalFindings)
        )
    }

    private static func makeSummary(
        keywordAnalysis: KeywordAnalysis,
        sectionAnalysis: SectionAnalysis,
        contactAnalysis: ContactAnalysis,
        formatAnalysis: FormatAnalysis
    ) -> String {
        var parts: [String] = []
        parts.append("Matched \(keywordAnalysis.matched.count) of \(keywordAnalysis.totalWeightedTerms) weighted JD keywords.")

        if let primaryGap = keywordAnalysis.missing.first {
            parts.append("Biggest keyword gap: \(primaryGap).")
        }

        if sectionAnalysis.score < 100 {
            parts.append("Required ATS sections are incomplete.")
        }

        if contactAnalysis.score < 100 {
            parts.append("Contact parsing needs cleanup.")
        } else if formatAnalysis.score == 100 {
            parts.append("Pipeline's exported PDF remains machine-readable.")
        }

        return parts.joined(separator: " ")
    }

    private static func accumulateSpecialTerms(
        in text: String,
        weightMultiplier: Double,
        isTitle: Bool,
        into candidates: inout [String: WeightedKeyword]
    ) {
        let lowered = text.lowercased()

        for term in specialTerms {
            let occurrences = term.aliases.reduce(0) { partialResult, alias in
                partialResult + countOccurrences(
                    of: alias.lowercased(),
                    in: lowered,
                    usesWordBoundaries: term.usesWordBoundaries
                )
            }
            guard occurrences > 0 else { continue }

            let key = specialKey(for: term.display)
            var candidate = candidates[key] ?? WeightedKeyword(
                display: term.display,
                normalized: key,
                specialTerm: term,
                weight: 0,
                occurrences: 0,
                isTitleTerm: false
            )
            candidate.weight += Double(occurrences) * weightMultiplier
            candidate.occurrences += occurrences
            candidate.isTitleTerm = candidate.isTitleTerm || isTitle
            candidates[key] = candidate
        }
    }

    private static func accumulateTokens(
        in text: String,
        weightMultiplier: Double,
        into candidates: inout [String: WeightedKeyword]
    ) {
        let tokens = normalizedWords(from: text)
        guard !tokens.isEmpty else { return }

        var counts: [String: Int] = [:]
        for token in tokens {
            counts[token, default: 0] += 1
        }

        for (token, occurrences) in counts {
            var candidate = candidates[token] ?? WeightedKeyword(
                display: token.uppercased() == token ? token : token.capitalizedIfNeeded(),
                normalized: token,
                specialTerm: nil,
                weight: 0,
                occurrences: 0,
                isTitleTerm: false
            )
            candidate.weight += Double(occurrences) * weightMultiplier
            candidate.occurrences += occurrences
            candidate.isTitleTerm = candidate.isTitleTerm || weightMultiplier > 1.5
            candidates[token] = candidate
        }
    }

    private static func accumulatePhrases(
        in text: String,
        weightMultiplier: Double,
        into candidates: inout [String: WeightedKeyword]
    ) {
        let tokens = normalizedWords(from: text)
        guard tokens.count >= 2 else { return }

        var counts: [String: Int] = [:]
        for index in 0..<(tokens.count - 1) {
            let phrase = "\(tokens[index]) \(tokens[index + 1])"
            counts[phrase, default: 0] += 1
        }

        for (phrase, occurrences) in counts where occurrences > 1 || weightMultiplier > 2.0 {
            var candidate = candidates[phrase] ?? WeightedKeyword(
                display: phrase.capitalizedPhrase(),
                normalized: phrase,
                specialTerm: nil,
                weight: 0,
                occurrences: 0,
                isTitleTerm: false
            )
            candidate.weight += Double(occurrences) * weightMultiplier
            candidate.occurrences += occurrences
            candidate.isTitleTerm = candidate.isTitleTerm || weightMultiplier > 2.0
            candidates[phrase] = candidate
        }
    }

    private static func keyword(
        _ candidate: WeightedKeyword,
        appearsIn rawText: String,
        normalizedText: String
    ) -> Bool {
        if let specialTerm = candidate.specialTerm {
            return specialTerm.aliases.contains { alias in
                countOccurrences(
                    of: alias.lowercased(),
                    in: rawText.lowercased(),
                    usesWordBoundaries: specialTerm.usesWordBoundaries
                ) > 0
            }
        }

        let needle = " \(candidate.normalized) "
        return normalizedText.contains(needle)
    }

    private static func resumeSearchText(from resume: ResumeSchema) -> String {
        var text = "\(resume.name) \(resume.contact.phone) \(resume.contact.email) \(resume.contact.linkedin) \(resume.contact.github)"
        if let summary = resume.summary {
            text.append(" \(summary)")
        }
        for entry in resume.education {
            text.append(" \(entry.university) \(entry.location) \(entry.degree) \(entry.date)")
        }
        for entry in resume.experience {
            text.append(" \(entry.title) \(entry.company) \(entry.location) \(entry.dates) \(entry.responsibilities.joined(separator: " "))")
        }
        for project in resume.projects {
            text.append(" \(project.name) \(project.url ?? "") \(project.technologies.joined(separator: " ")) \(project.date) \(project.description.joined(separator: " "))")
        }
        for (category, values) in resume.skills {
            text.append(" \(category) \(values.joined(separator: " "))")
        }
        return text
    }

    private static func normalizedSearchText(from text: String) -> String {
        " " + normalizePhrase(text) + " "
    }

    private static func normalizePhrase(_ value: String) -> String {
        normalizedWords(from: value).joined(separator: " ")
    }

    private static func specialKey(for value: String) -> String {
        let normalized = normalizePhrase(value)
        if !normalized.isEmpty {
            return normalized
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedWords(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { token in
                token.count >= 3 && !stopWords.contains(token)
            }
    }

    private static func countOccurrences(
        of term: String,
        in text: String,
        usesWordBoundaries: Bool
    ) -> Int {
        guard !term.isEmpty, !text.isEmpty else { return 0 }
        let pattern = usesWordBoundaries
            ? "(?<![[:alnum:]])" + NSRegularExpression.escapedPattern(for: term) + "(?![[:alnum:]])"
            : NSRegularExpression.escapedPattern(for: term)

        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return 0
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.numberOfMatches(in: text, options: [], range: range)
    }

    private static func wordCount(_ value: String) -> Int {
        value
            .split(whereSeparator: \.isWhitespace)
            .count
    }

    private static func longBulletCount(in resume: ResumeSchema) -> Int {
        let experienceBullets = resume.experience.flatMap(\.responsibilities)
        let projectBullets = resume.projects.flatMap(\.description)
        return (experienceBullets + projectBullets).reduce(0) { partialResult, bullet in
            partialResult + (wordCount(bullet) > 32 ? 1 : 0)
        }
    }

    private static func isValidEmail(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.range(
            of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isValidPhone(_ value: String) -> Bool {
        let digits = value.filter { $0.isNumber }
        return digits.count >= 10 && digits.count <= 15
    }

    private static func isLikelyProfileURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
            ? trimmed
            : "https://\(trimmed)"
        return URL(string: normalized)?.host != nil
    }

    private static func atsResumeSourceKind(for kind: ResumeSourceSelection.Kind) -> ATSResumeSourceKind {
        switch kind {
        case .tailoredSnapshot:
            return .tailoredSnapshot
        case .masterResume:
            return .masterResume
        }
    }

    private static func deduplicated(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for value in values {
            guard seen.insert(value).inserted else { continue }
            ordered.append(value)
        }
        return ordered
    }
}

private extension String {
    func capitalizedIfNeeded() -> String {
        if count <= 4 {
            return uppercased()
        }
        return capitalized
    }

    func capitalizedPhrase() -> String {
        split(separator: " ")
            .map { token in
                let value = String(token)
                return value.capitalizedIfNeeded()
            }
            .joined(separator: " ")
    }
}
