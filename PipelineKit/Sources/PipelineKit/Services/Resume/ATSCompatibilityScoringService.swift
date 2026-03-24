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
    public let skillsPromotionKeywords: [String]
    public let keywordEvidenceSummary: [String]
    public let criticalFindings: [String]
    public let warningFindings: [String]
    public let sectionFindings: [String]
    public let contactWarningFindings: [String]
    public let contactCriticalFindings: [String]
    public let formatWarningFindings: [String]
    public let formatCriticalFindings: [String]
    public let hasExperienceSection: Bool
    public let hasEducationSection: Bool
    public let hasSkillsSection: Bool
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
        skillsPromotionKeywords: [String],
        keywordEvidenceSummary: [String],
        criticalFindings: [String],
        warningFindings: [String],
        sectionFindings: [String],
        contactWarningFindings: [String],
        contactCriticalFindings: [String],
        formatWarningFindings: [String],
        formatCriticalFindings: [String],
        hasExperienceSection: Bool,
        hasEducationSection: Bool,
        hasSkillsSection: Bool,
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
        self.skillsPromotionKeywords = skillsPromotionKeywords
        self.keywordEvidenceSummary = keywordEvidenceSummary
        self.criticalFindings = criticalFindings
        self.warningFindings = warningFindings
        self.sectionFindings = sectionFindings
        self.contactWarningFindings = contactWarningFindings
        self.contactCriticalFindings = contactCriticalFindings
        self.formatWarningFindings = formatWarningFindings
        self.formatCriticalFindings = formatCriticalFindings
        self.hasExperienceSection = hasExperienceSection
        self.hasEducationSection = hasEducationSection
        self.hasSkillsSection = hasSkillsSection
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
    public static let scoringVersion = "ats-compat-v3"

    private static let keywordWeight = 0.55
    private static let sectionWeight = 0.20
    private static let contactWeight = 0.15
    private static let formatWeight = 0.10
    private static let bannedExtractedTerms: Set<String> = [
        "they", "them", "their", "theirs", "we", "our", "ours", "us",
        "you", "your", "yours", "company", "employer", "candidate", "applicant"
    ]

    private struct SpecialTerm {
        let display: String
        let aliases: [String]
        let usesWordBoundaries: Bool
    }

    private struct SearchAlias {
        let value: String
        let usesWordBoundaries: Bool
    }

    private struct SearchKeyword {
        let display: String
        let normalized: String
        let aliases: [SearchAlias]
    }

    private struct KeywordAnalysis {
        let score: Int
        let matched: [String]
        let missing: [String]
        let skillsPromotionKeywords: [String]
        let keywordEvidenceSummary: [String]
        let criticalFindings: [String]
        let warningFindings: [String]
        let totalWeightedTerms: Int
    }

    private struct SectionAnalysis {
        let score: Int
        let hasExperienceSection: Bool
        let hasEducationSection: Bool
        let hasSkillsSection: Bool
        let findings: [String]
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

    public static func prepareDraft(
        application: JobApplication,
        resumeSource: ResumeSourceSelection?,
        extractedKeywords: [ATSKeywordCandidate],
        referenceDate: Date = Date()
    ) throws -> ATSCompatibilityAssessmentDraft {
        guard let resumeSource else {
            return blockedDraft(
                reason: .missingResumeSource,
                application: application,
                resumeSource: nil,
                message: nil,
                referenceDate: referenceDate
            )
        }

        let description = application.jobDescription?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !description.isEmpty else {
            return blockedDraft(
                reason: .missingJobDescription,
                application: application,
                resumeSource: resumeSource,
                message: nil,
                referenceDate: referenceDate
            )
        }

        let validation = try ResumeSchemaValidator.validate(jsonText: resumeSource.rawJSON)
        let resume = validation.schema

        let keywordAnalysis = analyzeKeywords(
            extractedKeywords: sanitizeExtractedKeywords(
                extractedKeywords,
                companyName: application.companyName
            ),
            resume: resume
        )
        let sectionAnalysis = analyzeSections(resume: resume)
        let contactAnalysis = analyzeContact(resume: resume)
        let formatAnalysis = analyzeFormat(
            resume: resume,
            unknownFieldPaths: validation.unknownFieldPaths
        )

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
            skillsPromotionKeywords: keywordAnalysis.skillsPromotionKeywords,
            keywordEvidenceSummary: keywordAnalysis.keywordEvidenceSummary,
            criticalFindings: deduplicated(
                keywordAnalysis.criticalFindings
                + contactAnalysis.criticalFindings
                + formatAnalysis.criticalFindings
            ),
            warningFindings: deduplicated(
                keywordAnalysis.warningFindings
                + sectionAnalysis.findings
                + contactAnalysis.warningFindings
                + formatAnalysis.warningFindings
            ),
            sectionFindings: sectionAnalysis.findings,
            contactWarningFindings: contactAnalysis.warningFindings,
            contactCriticalFindings: contactAnalysis.criticalFindings,
            formatWarningFindings: formatAnalysis.warningFindings,
            formatCriticalFindings: formatAnalysis.criticalFindings,
            hasExperienceSection: sectionAnalysis.hasExperienceSection,
            hasEducationSection: sectionAnalysis.hasEducationSection,
            hasSkillsSection: sectionAnalysis.hasSkillsSection,
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
        message: String? = nil,
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
            skillsPromotionKeywords: [],
            keywordEvidenceSummary: [],
            criticalFindings: [],
            warningFindings: [],
            sectionFindings: [],
            contactWarningFindings: [],
            contactCriticalFindings: [],
            formatWarningFindings: [],
            formatCriticalFindings: [],
            hasExperienceSection: false,
            hasEducationSection: false,
            hasSkillsSection: false,
            status: .blocked,
            blockedReason: reason,
            resumeSourceKind: resumeSource.map { atsResumeSourceKind(for: $0.kind) },
            resumeSourceSnapshotID: resumeSource?.snapshotID,
            resumeSourceRevisionID: resumeSource?.masterRevisionID,
            resumeSourceFingerprint: resumeSource.flatMap(resumeSourceFingerprint(for:)),
            lastErrorMessage: message,
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
            case .missingAIConfiguration:
                return false
            case .none:
                return true
            }
        }

        if assessment.status == .failed {
            return isStale(assessment, application: application, resumeSource: resumeSource)
        }

        return isStale(assessment, application: application, resumeSource: resumeSource)
    }

    public static func evidencePaths(
        for keyword: String,
        aliases: [String] = [],
        in resume: ResumeSchema
    ) -> [String] {
        let searchTerm = searchKeyword(for: keyword, aliases: aliases)
        var paths: [String] = []

        if let summary = resume.summary,
           Self.keyword(searchTerm, appearsIn: summary, normalizedText: normalizedSearchText(from: summary)) {
            paths.append("/summary")
        }

        for (index, entry) in resume.experience.enumerated() {
            if Self.keyword(searchTerm, appearsIn: entry.title, normalizedText: normalizedSearchText(from: entry.title)) {
                paths.append("/experience/\(index)/title")
            }
            if Self.keyword(searchTerm, appearsIn: entry.company, normalizedText: normalizedSearchText(from: entry.company)) {
                paths.append("/experience/\(index)/company")
            }
            for (bulletIndex, bullet) in entry.responsibilities.enumerated() {
                if Self.keyword(searchTerm, appearsIn: bullet, normalizedText: normalizedSearchText(from: bullet)) {
                    paths.append("/experience/\(index)/responsibilities/\(bulletIndex)")
                }
            }
        }

        for (index, project) in resume.projects.enumerated() {
            if Self.keyword(searchTerm, appearsIn: project.name, normalizedText: normalizedSearchText(from: project.name)) {
                paths.append("/projects/\(index)/name")
            }
            for (technologyIndex, technology) in project.technologies.enumerated() {
                if Self.keyword(searchTerm, appearsIn: technology, normalizedText: normalizedSearchText(from: technology)) {
                    paths.append("/projects/\(index)/technologies/\(technologyIndex)")
                }
            }
            for (descriptionIndex, bullet) in project.description.enumerated() {
                if Self.keyword(searchTerm, appearsIn: bullet, normalizedText: normalizedSearchText(from: bullet)) {
                    paths.append("/projects/\(index)/description/\(descriptionIndex)")
                }
            }
        }

        return deduplicated(paths)
    }

    private static func analyzeKeywords(
        extractedKeywords: [ATSKeywordCandidate],
        resume: ResumeSchema
    ) -> KeywordAnalysis {
        let selected = deduplicatedKeywords(extractedKeywords)

        guard !selected.isEmpty else {
            return KeywordAnalysis(
                score: 0,
                matched: [],
                missing: [],
                skillsPromotionKeywords: [],
                keywordEvidenceSummary: [],
                criticalFindings: [],
                warningFindings: ["No ATS keywords were extracted from the job description."],
                totalWeightedTerms: 0
            )
        }

        let resumeRawText = resumeSearchText(from: resume)
        let resumeNormalizedText = normalizedSearchText(from: resumeRawText)
        let skillsRawText = resumeSkillsSearchText(from: resume)
        let skillsNormalizedText = normalizedSearchText(from: skillsRawText)

        var matched: [String] = []
        var missing: [String] = []
        var skillsPromotionKeywords: [String] = []
        var keywordEvidenceSummary: [String] = []
        var matchedWeight = 0.0
        var totalWeight = 0.0
        var criticalFindings: [String] = []
        var warningFindings: [String] = []

        for candidate in selected {
            let searchTerm = searchKeyword(for: candidate)
            let evidencePaths = evidencePaths(
                for: candidate.term,
                aliases: candidate.aliases,
                in: resume
            )
            let weight = keywordWeight(for: candidate)
            let importanceDescriptor = candidate.importance == .core ? "core JD requirement" : "supporting JD requirement"
            totalWeight += weight

            let matchedAnywhere = keyword(searchTerm, appearsIn: resumeRawText, normalizedText: resumeNormalizedText)
            let matchedInSkills = keyword(searchTerm, appearsIn: skillsRawText, normalizedText: skillsNormalizedText)

            if matchedAnywhere {
                matched.append(candidate.term)
                matchedWeight += weight

                if candidate.kind != .roleConcept && !matchedInSkills && !evidencePaths.isEmpty {
                    skillsPromotionKeywords.append(candidate.term)
                    warningFindings.append("\(candidate.term) appears in resume evidence but is not listed in Skills.")
                    keywordEvidenceSummary.append(
                        "\(candidate.term) is a \(importanceDescriptor) and only appears outside the Skills section."
                    )
                } else {
                    keywordEvidenceSummary.append(
                        "\(candidate.term) is a \(importanceDescriptor) and already appears in the resume."
                    )
                }
            } else {
                missing.append(candidate.term)
                if candidate.importance == .core {
                    let message = "\(candidate.term) is a \(importanceDescriptor) and is absent from the resume."
                    criticalFindings.append(message)
                    keywordEvidenceSummary.append(message)
                }
            }
        }

        let score = totalWeight > 0
            ? Int(((matchedWeight / totalWeight) * 100).rounded())
            : 0

        if !missing.isEmpty {
            warningFindings.append("\(missing.count) of \(selected.count) extracted ATS keywords are missing from the resume.")
        }

        if !skillsPromotionKeywords.isEmpty {
            warningFindings.append(
                "\(skillsPromotionKeywords.count) ATS keyword\(skillsPromotionKeywords.count == 1 ? "" : "s") can be promoted into the Skills section from existing resume evidence."
            )
        }

        return KeywordAnalysis(
            score: score,
            matched: deduplicated(matched),
            missing: deduplicated(missing),
            skillsPromotionKeywords: deduplicated(skillsPromotionKeywords),
            keywordEvidenceSummary: deduplicated(keywordEvidenceSummary),
            criticalFindings: deduplicated(criticalFindings),
            warningFindings: deduplicated(warningFindings),
            totalWeightedTerms: selected.count
        )
    }

    private static func analyzeSections(resume: ResumeSchema) -> SectionAnalysis {
        let hasExperienceSection = !resume.experience.isEmpty
        let hasEducationSection = !resume.education.isEmpty
        let hasSkillsSection = !resume.skills.isEmpty

        let presentCount = [hasExperienceSection, hasEducationSection, hasSkillsSection]
            .filter { $0 }
            .count

        var findings: [String] = []
        if !hasExperienceSection {
            findings.append("Experience section is missing or empty.")
        }
        if !hasEducationSection {
            findings.append("Education section is missing or empty.")
        }
        if !hasSkillsSection {
            findings.append("Skills section is missing or empty.")
        }

        let score = Int((Double(presentCount) / 3.0 * 100.0).rounded())
        return SectionAnalysis(
            score: score,
            hasExperienceSection: hasExperienceSection,
            hasEducationSection: hasEducationSection,
            hasSkillsSection: hasSkillsSection,
            findings: findings
        )
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
            warningFindings: deduplicated(warningFindings),
            criticalFindings: deduplicated(criticalFindings)
        )
    }

    private static func analyzeFormat(
        resume: ResumeSchema,
        unknownFieldPaths: [String]
    ) -> FormatAnalysis {
        var score = 100
        var warningFindings: [String] = []
        var criticalFindings: [String] = []

        if let summary = resume.summary,
           wordCount(summary) > 80 {
            score -= 12
            warningFindings.append("Summary is longer than 80 words.")
        }

        if resume.experience.contains(where: { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            score -= 15
            criticalFindings.append("At least one experience entry is missing a title.")
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
            warningFindings.append("Skills section is dense and exports as long comma-separated lines, which some ATS systems parse poorly.")
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

        if !unknownFieldPaths.isEmpty {
            score -= min(10, unknownFieldPaths.count * 2)
            warningFindings.append(
                "\(unknownFieldPaths.count) resume field\(unknownFieldPaths.count == 1 ? "" : "s") are not rendered by Pipeline exports and may be omitted from ATS-visible output."
            )
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
        parts.append("Matched \(keywordAnalysis.matched.count) of \(keywordAnalysis.totalWeightedTerms) extracted ATS keywords.")

        if let primaryGap = keywordAnalysis.missing.first {
            parts.append("Biggest missing keyword: \(primaryGap).")
        }

        if !keywordAnalysis.skillsPromotionKeywords.isEmpty {
            parts.append("\(keywordAnalysis.skillsPromotionKeywords.count) keyword\(keywordAnalysis.skillsPromotionKeywords.count == 1 ? "" : "s") can be promoted into Skills from existing resume evidence.")
        }

        if sectionAnalysis.score < 100 {
            parts.append("Required ATS sections are incomplete.")
        }

        if contactAnalysis.score < 100 {
            parts.append("Contact parsing needs cleanup.")
        }

        if formatAnalysis.score == 100 {
            parts.append("Pipeline's structured export remains ATS-friendly.")
        }

        return parts.joined(separator: " ")
    }

    private static func searchKeyword(for keyword: String, aliases: [String] = []) -> SearchKeyword {
        if let specialTerm = specialTerms.first(where: {
            $0.display.caseInsensitiveCompare(keyword) == .orderedSame
                || specialKey(for: $0.display) == specialKey(for: keyword)
        }) {
            return SearchKeyword(
                display: specialTerm.display,
                normalized: specialKey(for: specialTerm.display),
                aliases: specialTerm.aliases.map {
                    SearchAlias(value: $0.lowercased(), usesWordBoundaries: specialTerm.usesWordBoundaries)
                }
            )
        }

        let aliasValues = deduplicated([keyword] + aliases)
        return SearchKeyword(
            display: keyword,
            normalized: normalizePhrase(keyword),
            aliases: aliasValues.map { alias in
                SearchAlias(
                    value: alias.lowercased(),
                    usesWordBoundaries: shouldUseWordBoundaries(for: alias)
                )
            }
        )
    }

    private static func searchKeyword(for candidate: ATSKeywordCandidate) -> SearchKeyword {
        let aliases = candidate.aliases + supplementalAliases(for: candidate.term)
        return searchKeyword(for: candidate.term, aliases: aliases)
    }

    private static func keyword(
        _ searchKeyword: SearchKeyword,
        appearsIn rawText: String,
        normalizedText: String
    ) -> Bool {
        let loweredRawText = rawText.lowercased()
        if searchKeyword.aliases.contains(where: { alias in
            countOccurrences(
                of: alias.value,
                in: loweredRawText,
                usesWordBoundaries: alias.usesWordBoundaries
            ) > 0
        }) {
            return true
        }

        let needle = " \(searchKeyword.normalized) "
        return !searchKeyword.normalized.isEmpty && normalizedText.contains(needle)
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
        text.append(" \(resumeSkillsSearchText(from: resume))")
        return text
    }

    private static func resumeSkillsSearchText(from resume: ResumeSchema) -> String {
        resume.skills
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { category, values in
                "\(category) \(values.joined(separator: " "))"
            }
            .joined(separator: " ")
    }

    private static func normalizedSearchText(from text: String) -> String {
        " " + normalizePhrase(text) + " "
    }

    private static func normalizePhrase(_ value: String) -> String {
        searchWords(from: value).joined(separator: " ")
    }

    private static func specialKey(for value: String) -> String {
        let normalized = normalizePhrase(value)
        if !normalized.isEmpty {
            return normalized
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func searchWords(from text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
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

    private static func keywordWeight(for candidate: ATSKeywordCandidate) -> Double {
        let importanceWeight = candidate.importance == .core ? 1.6 : 1.0
        let kindWeight: Double
        switch candidate.kind {
        case .roleConcept:
            kindWeight = 0.9
        case .hardSkill, .tool, .platform, .domain:
            kindWeight = 1.0
        }
        return importanceWeight * kindWeight
    }

    private static func deduplicatedKeywords(_ keywords: [ATSKeywordCandidate]) -> [ATSKeywordCandidate] {
        var seen = Set<String>()
        var ordered: [ATSKeywordCandidate] = []

        for keyword in keywords {
            guard ordered.count < 15 else { break }
            let normalized = specialKey(for: keyword.term)
            guard !normalized.isEmpty else { continue }
            guard seen.insert(normalized).inserted else { continue }
            ordered.append(keyword)
        }

        return ordered
    }

    private static func sanitizeExtractedKeywords(
        _ keywords: [ATSKeywordCandidate],
        companyName: String
    ) -> [ATSKeywordCandidate] {
        let normalizedCompanyName = specialKey(for: companyName)

        return keywords.filter { keyword in
            let normalized = specialKey(for: keyword.term)
            guard !normalized.isEmpty else { return false }
            guard !bannedExtractedTerms.contains(normalized) else { return false }
            return normalized != normalizedCompanyName
        }
    }

    private static func shouldUseWordBoundaries(for alias: String) -> Bool {
        alias.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.whitespaces.contains($0)
        }
    }

    private static func supplementalAliases(for term: String) -> [String] {
        guard let specialTerm = specialTerms.first(where: {
            $0.display.caseInsensitiveCompare(term) == .orderedSame
                || specialKey(for: $0.display) == specialKey(for: term)
        }) else {
            return []
        }

        return specialTerm.aliases
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
