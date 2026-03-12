import Foundation
import SwiftData

public struct CompanyResearchSourcePayload: Sendable, Equatable {
    public let title: String
    public let urlString: String
    public let sourceKind: CompanyResearchSourceKind
    public let fetchStatus: CompanyResearchFetchStatus
    public let contentExcerpt: String?
    public let fetchedText: String?
    public let errorMessage: String?
    public let orderIndex: Int
    public let resolvedURLString: String?
    public let validationStatus: ResearchValidationStatus
    public let acquisitionMethod: ResearchAcquisitionMethod
    public let validationReason: String?
    public let confidence: ResearchConfidence?
    public let citationPayload: String?
    public let fetchedAt: Date?
    public let validatedAt: Date?

    public init(
        title: String,
        urlString: String,
        sourceKind: CompanyResearchSourceKind,
        fetchStatus: CompanyResearchFetchStatus,
        contentExcerpt: String?,
        fetchedText: String?,
        errorMessage: String?,
        orderIndex: Int,
        resolvedURLString: String? = nil,
        validationStatus: ResearchValidationStatus = .skipped,
        acquisitionMethod: ResearchAcquisitionMethod = .none,
        validationReason: String? = nil,
        confidence: ResearchConfidence? = nil,
        citationPayload: String? = nil,
        fetchedAt: Date? = nil,
        validatedAt: Date? = nil
    ) {
        self.title = title
        self.urlString = urlString
        self.sourceKind = sourceKind
        self.fetchStatus = fetchStatus
        self.contentExcerpt = contentExcerpt
        self.fetchedText = fetchedText
        self.errorMessage = errorMessage
        self.orderIndex = orderIndex
        self.resolvedURLString = resolvedURLString
        self.validationStatus = validationStatus
        self.acquisitionMethod = acquisitionMethod
        self.validationReason = validationReason
        self.confidence = confidence
        self.citationPayload = citationPayload
        self.fetchedAt = fetchedAt
        self.validatedAt = validatedAt
    }

    public var synthesisEligible: Bool {
        switch validationStatus {
        case .verified, .partial, .manual:
            return fetchedText?.isEmpty == false || contentExcerpt?.isEmpty == false
        case .blocked, .invalid, .skipped:
            return false
        }
    }
}

public struct CompanyResearchSalaryFinding: Sendable, Equatable {
    public let roleTitle: String
    public let location: String
    public let sourceName: String
    public let sourceURLString: String?
    public let notes: String?
    public let confidenceNotes: String?
    public let currency: Currency
    public let minBaseCompensation: Int?
    public let maxBaseCompensation: Int?
    public let minTotalCompensation: Int?
    public let maxTotalCompensation: Int?

    public init(
        roleTitle: String,
        location: String,
        sourceName: String,
        sourceURLString: String? = nil,
        notes: String? = nil,
        confidenceNotes: String? = nil,
        currency: Currency,
        minBaseCompensation: Int? = nil,
        maxBaseCompensation: Int? = nil,
        minTotalCompensation: Int? = nil,
        maxTotalCompensation: Int? = nil
    ) {
        self.roleTitle = roleTitle
        self.location = location
        self.sourceName = sourceName
        self.sourceURLString = sourceURLString
        self.notes = notes
        self.confidenceNotes = confidenceNotes
        self.currency = currency
        self.minBaseCompensation = minBaseCompensation
        self.maxBaseCompensation = maxBaseCompensation
        self.minTotalCompensation = minTotalCompensation
        self.maxTotalCompensation = maxTotalCompensation
    }
}

public struct CompanyResearchResult: Sendable, Equatable {
    public let websiteURL: String?
    public let linkedInURL: String?
    public let glassdoorURL: String?
    public let levelsFYIURL: String?
    public let teamBlindURL: String?
    public let industry: String?
    public let sizeBand: CompanySizeBand?
    public let headquarters: String?
    public let summary: String?
    public let summaryConfidenceNote: String?
    public let runStatus: ResearchRunStatus
    public let failureMessage: String?
    public let sources: [CompanyResearchSourcePayload]
    public let salaryFindings: [CompanyResearchSalaryFinding]
    public let usage: AIUsageMetrics?
    public let rawResponseText: String

    public init(
        websiteURL: String?,
        linkedInURL: String?,
        glassdoorURL: String?,
        levelsFYIURL: String?,
        teamBlindURL: String?,
        industry: String?,
        sizeBand: CompanySizeBand?,
        headquarters: String?,
        summary: String?,
        summaryConfidenceNote: String? = nil,
        runStatus: ResearchRunStatus = .succeeded,
        failureMessage: String? = nil,
        sources: [CompanyResearchSourcePayload],
        salaryFindings: [CompanyResearchSalaryFinding],
        usage: AIUsageMetrics?,
        rawResponseText: String
    ) {
        self.websiteURL = websiteURL
        self.linkedInURL = linkedInURL
        self.glassdoorURL = glassdoorURL
        self.levelsFYIURL = levelsFYIURL
        self.teamBlindURL = teamBlindURL
        self.industry = industry
        self.sizeBand = sizeBand
        self.headquarters = headquarters
        self.summary = summary
        self.summaryConfidenceNote = summaryConfidenceNote
        self.runStatus = runStatus
        self.failureMessage = failureMessage
        self.sources = sources
        self.salaryFindings = salaryFindings
        self.usage = usage
        self.rawResponseText = rawResponseText
    }
}

public protocol CompanyResearchSearchProviding: Sendable {
    func groundedWebSearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse
}

public struct DefaultCompanyResearchSearchProvider: CompanyResearchSearchProviding {
    public init() {}

    public func groundedWebSearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        query: String,
        systemPrompt: String?,
        domains: [String],
        maxTokens: Int
    ) async throws -> AIWebSearchResponse {
        try await AICompletionClient.groundedWebSearch(
            provider: provider,
            apiKey: apiKey,
            model: model,
            query: query,
            systemPrompt: systemPrompt,
            domains: domains,
            maxTokens: maxTokens
        )
    }
}

public enum CompanyResearchService {
    private struct CandidateSource: Sendable {
        let title: String
        let urlString: String
        let sourceKind: CompanyResearchSourceKind
    }

    private struct SearchIntent: Sendable {
        let title: String
        let query: String
        let domains: [String]
        let sourceKind: CompanyResearchSourceKind
    }

    public static func generateResearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        company: CompanyProfile,
        application: JobApplication? = nil,
        webContentProvider: WebContentProvider = BasicWebContentProvider(serviceName: "CompanyResearch"),
        searchProvider: CompanyResearchSearchProviding = DefaultCompanyResearchSearchProvider()
    ) async throws -> CompanyResearchResult {
        let excludedURLs = Set(company.sortedResearchSources.filter(\.isExcludedFromResearch).map(\.urlString))
        let directCandidates = candidateSources(
            company: company,
            application: application,
            excludedURLs: excludedURLs
        )

        var sourcePayloads = await collectDirectSourcePayloads(
            from: directCandidates,
            company: company,
            application: application,
            via: webContentProvider
        )

        if let manualSource = manualSourcePayload(company: company, orderIndex: sourcePayloads.count) {
            sourcePayloads.append(manualSource)
        }

        if AICompletionClient.supportsWebSearch(provider: provider, model: model) {
            let searchPayloads = await collectProviderSearchPayloads(
                provider: provider,
                apiKey: apiKey,
                model: model,
                company: company,
                application: application,
                via: searchProvider,
                startIndex: sourcePayloads.count
            )
            sourcePayloads.append(contentsOf: searchPayloads)
        }

        let dedupedPayloads = deduplicateSourcePayloads(sourcePayloads)
        let usableSources = dedupedPayloads.filter(\.synthesisEligible)

        guard !usableSources.isEmpty else {
            return CompanyResearchResult(
                websiteURL: verifiedSourceURL(of: .companyWebsite, in: dedupedPayloads) ?? company.websiteURL,
                linkedInURL: verifiedSourceURL(of: .linkedIn, in: dedupedPayloads) ?? company.linkedInURL,
                glassdoorURL: verifiedSourceURL(of: .glassdoor, in: dedupedPayloads) ?? company.glassdoorURL,
                levelsFYIURL: verifiedSourceURL(of: .levelsFYI, in: dedupedPayloads) ?? company.levelsFYIURL,
                teamBlindURL: verifiedSourceURL(of: .teamBlind, in: dedupedPayloads) ?? company.teamBlindURL,
                industry: company.industry,
                sizeBand: company.sizeBand,
                headquarters: company.headquarters,
                summary: nil,
                summaryConfidenceNote: "No verified source content was available. Add a company link or manual note and retry.",
                runStatus: .failed,
                failureMessage: "No verified evidence was available for this company.",
                sources: dedupedPayloads,
                salaryFindings: [],
                usage: nil,
                rawResponseText: ""
            )
        }

        let prompt = makePrompt(company: company, application: application, sources: usableSources)
        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            maxTokens: 40_000,
            temperature: 0.2
        )

        return try parseResponse(
            response.text,
            usage: response.usage,
            sourcePayloads: dedupedPayloads
        )
    }

    @discardableResult
    public static func applyResearchResult(
        _ result: CompanyResearchResult,
        to company: CompanyProfile,
        provider: AIProvider,
        model: String,
        applicationID: UUID?,
        requestStatus: AIUsageRequestStatus,
        startedAt: Date,
        finishedAt: Date = Date(),
        errorMessage: String? = nil,
        in modelContext: ModelContext
    ) throws -> CompanyResearchSnapshot {
        if company.websiteURL == nil {
            company.websiteURL = CompanyProfile.normalizedURLString(result.websiteURL)
        }
        if company.linkedInURL == nil {
            company.linkedInURL = CompanyProfile.normalizedURLString(result.linkedInURL)
        }
        if company.glassdoorURL == nil {
            company.glassdoorURL = CompanyProfile.normalizedURLString(result.glassdoorURL)
        }
        if company.levelsFYIURL == nil {
            company.levelsFYIURL = CompanyProfile.normalizedURLString(result.levelsFYIURL)
        }
        if company.teamBlindURL == nil {
            company.teamBlindURL = CompanyProfile.normalizedURLString(result.teamBlindURL)
        }
        if company.industry == nil {
            company.industry = CompanyProfile.normalizedText(result.industry)
        }
        if company.headquarters == nil {
            company.headquarters = CompanyProfile.normalizedText(result.headquarters)
        }
        if company.sizeBand == nil {
            company.sizeBand = result.sizeBand
        }

        company.touchResearch(at: finishedAt, summary: result.summary)
        if !result.salaryFindings.isEmpty {
            company.touchSalaryResearch(at: finishedAt)
        }

        let snapshot = CompanyResearchSnapshot(
            providerID: provider.providerID,
            model: model,
            requestStatus: requestStatus,
            runStatus: result.runStatus,
            summaryText: result.summary,
            summaryConfidenceNote: result.summaryConfidenceNote,
            rawResponseText: result.rawResponseText,
            errorMessage: errorMessage ?? result.failureMessage,
            startedAt: startedAt,
            finishedAt: finishedAt,
            applicationID: applicationID,
            company: company
        )
        modelContext.insert(snapshot)

        for sourcePayload in result.sources {
            let excluded = company.sortedResearchSources.first(where: {
                $0.urlString == sourcePayload.urlString || $0.resolvedURLString == sourcePayload.resolvedURLString
            })?.isExcludedFromResearch ?? false

            let source = CompanyResearchSource(
                title: sourcePayload.title,
                urlString: sourcePayload.urlString,
                sourceKind: sourcePayload.sourceKind,
                fetchStatus: sourcePayload.fetchStatus,
                contentExcerpt: sourcePayload.contentExcerpt,
                resolvedURLString: sourcePayload.resolvedURLString,
                errorMessage: sourcePayload.errorMessage,
                validationStatus: sourcePayload.validationStatus,
                acquisitionMethod: sourcePayload.acquisitionMethod,
                validationReason: sourcePayload.validationReason,
                confidence: sourcePayload.confidence,
                citationPayload: sourcePayload.citationPayload,
                orderIndex: sourcePayload.orderIndex,
                fetchedAt: sourcePayload.fetchedAt,
                validatedAt: sourcePayload.validatedAt,
                isExcludedFromResearch: excluded,
                company: company,
                snapshot: snapshot
            )
            modelContext.insert(source)
        }

        for finding in result.salaryFindings {
            if let existing = company.sortedSalarySnapshots.first(where: {
                !$0.isUserEdited &&
                $0.sourceName.caseInsensitiveCompare(finding.sourceName) == .orderedSame &&
                $0.matches(roleTitle: finding.roleTitle, location: finding.location)
            }) {
                existing.update(
                    roleTitle: finding.roleTitle,
                    location: finding.location,
                    sourceName: finding.sourceName,
                    sourceURLString: finding.sourceURLString,
                    notes: finding.notes,
                    confidenceNotes: finding.confidenceNotes,
                    currency: finding.currency,
                    minBaseCompensation: finding.minBaseCompensation,
                    maxBaseCompensation: finding.maxBaseCompensation,
                    minTotalCompensation: finding.minTotalCompensation,
                    maxTotalCompensation: finding.maxTotalCompensation,
                    isUserEdited: false
                )
                existing.snapshot = snapshot
                existing.capturedAt = finishedAt
            } else {
                let salarySnapshot = CompanySalarySnapshot(
                    roleTitle: finding.roleTitle,
                    location: finding.location,
                    sourceName: finding.sourceName,
                    sourceURLString: finding.sourceURLString,
                    notes: finding.notes,
                    confidenceNotes: finding.confidenceNotes,
                    currency: finding.currency,
                    minBaseCompensation: finding.minBaseCompensation,
                    maxBaseCompensation: finding.maxBaseCompensation,
                    minTotalCompensation: finding.minTotalCompensation,
                    maxTotalCompensation: finding.maxTotalCompensation,
                    isUserEdited: false,
                    capturedAt: finishedAt,
                    company: company,
                    snapshot: snapshot
                )
                modelContext.insert(salarySnapshot)
            }
        }

        try modelContext.save()
        return snapshot
    }

    private static func candidateSources(
        company: CompanyProfile,
        application: JobApplication?,
        excludedURLs: Set<String>
    ) -> [CandidateSource] {
        var sources: [CandidateSource] = []

        func append(_ title: String, _ urlString: String?, _ kind: CompanyResearchSourceKind) {
            guard let normalizedURL = CompanyProfile.normalizedURLString(urlString),
                  !excludedURLs.contains(normalizedURL) else { return }
            sources.append(CandidateSource(title: title, urlString: normalizedURL, sourceKind: kind))
        }

        append("Company Website", company.websiteURL, .companyWebsite)
        append("Job Posting", application?.jobURL, .jobPosting)
        append(
            "LinkedIn",
            company.linkedInURL ?? URLHelpers.linkedInCompanyURL(companyName: company.name)?.absoluteString,
            .linkedIn
        )
        append("Glassdoor", company.glassdoorURL, .glassdoor)
        append("Levels.fyi", company.levelsFYIURL, .levelsFYI)
        append("TeamBlind", company.teamBlindURL, .teamBlind)

        return sources.uniquedPreservingOrder(by: \.urlString)
    }

    private static func searchIntents(
        company: CompanyProfile,
        application: JobApplication?
    ) -> [SearchIntent] {
        let roleFragment = application?.role.trimmingCharacters(in: .whitespacesAndNewlines)
        let locationFragment = application?.location.trimmingCharacters(in: .whitespacesAndNewlines)
        let scope = [roleFragment, locationFragment]
            .compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }
            .joined(separator: " ")

        func query(_ suffix: String) -> String {
            if scope.isEmpty {
                return "\(company.name) \(suffix)"
            }
            return "\(company.name) \(scope) \(suffix)"
        }

        return [
            SearchIntent(
                title: "Company Search",
                query: query("official website products company overview recent news"),
                domains: [],
                sourceKind: .companyWebsite
            ),
            SearchIntent(
                title: "Glassdoor Search",
                query: query("glassdoor reviews compensation"),
                domains: ["glassdoor.com"],
                sourceKind: .glassdoor
            ),
            SearchIntent(
                title: "Levels.fyi Search",
                query: query("levels.fyi compensation"),
                domains: ["levels.fyi"],
                sourceKind: .levelsFYI
            ),
            SearchIntent(
                title: "TeamBlind Search",
                query: query("teamblind culture interview experience"),
                domains: ["teamblind.com"],
                sourceKind: .teamBlind
            ),
            SearchIntent(
                title: "LinkedIn Search",
                query: query("linkedin company hiring"),
                domains: ["linkedin.com"],
                sourceKind: .linkedIn
            )
        ]
    }

    private static func collectDirectSourcePayloads(
        from candidates: [CandidateSource],
        company: CompanyProfile,
        application: JobApplication?,
        via provider: WebContentProvider
    ) async -> [CompanyResearchSourcePayload] {
        var payloads: [CompanyResearchSourcePayload] = []

        for (index, candidate) in candidates.enumerated() {
            let fetchedAt = Date()
            do {
                let result = try await provider.fetchContent(from: candidate.urlString)
                let normalizedText = normalizeEvidenceText(result.text)
                let validation = validateEvidence(
                    text: normalizedText,
                    company: company,
                    sourceKind: candidate.sourceKind,
                    requestedURLString: candidate.urlString,
                    resolvedURLString: result.resolvedURLString,
                    acquisitionMethod: result.acquisitionMethod,
                    fallbackTitle: candidate.title
                )

                payloads.append(
                    makePayload(
                        title: candidate.title,
                        urlString: candidate.urlString,
                        resolvedURLString: result.resolvedURLString,
                        sourceKind: validation.sourceKind,
                        acquisitionMethod: result.acquisitionMethod,
                        fetchStatus: validation.fetchStatus,
                        validationStatus: validation.validationStatus,
                        validationReason: validation.reason,
                        confidence: validation.confidence,
                        excerptText: normalizedText,
                        fetchedText: normalizedText,
                        errorMessage: nil,
                        citationPayload: nil,
                        orderIndex: index,
                        fetchedAt: fetchedAt
                    )
                )
            } catch {
                payloads.append(
                    makePayload(
                        title: candidate.title,
                        urlString: candidate.urlString,
                        resolvedURLString: nil,
                        sourceKind: candidate.sourceKind,
                        acquisitionMethod: .none,
                        fetchStatus: blockedFetchStatus(for: error),
                        validationStatus: blockedValidationStatus(for: error),
                        validationReason: error.localizedDescription,
                        confidence: .low,
                        excerptText: nil,
                        fetchedText: nil,
                        errorMessage: error.localizedDescription,
                        citationPayload: nil,
                        orderIndex: index,
                        fetchedAt: fetchedAt
                    )
                )
            }
        }

        return payloads
    }

    private static func collectProviderSearchPayloads(
        provider: AIProvider,
        apiKey: String,
        model: String,
        company: CompanyProfile,
        application: JobApplication?,
        via searchProvider: CompanyResearchSearchProviding,
        startIndex: Int
    ) async -> [CompanyResearchSourcePayload] {
        var payloads: [CompanyResearchSourcePayload] = []
        var nextIndex = startIndex

        for intent in searchIntents(company: company, application: application) {
            let fetchedAt = Date()

            do {
                let response = try await searchProvider.groundedWebSearch(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    query: intent.query,
                    systemPrompt: providerSearchSystemPrompt,
                    domains: intent.domains,
                    maxTokens: 900
                )

                let citations = response.citations.isEmpty
                    ? [AIWebSearchCitation(
                        title: intent.title,
                        urlString: siteRootURL(for: intent.domains.first) ?? "pipeline://search/\(intent.sourceKind.rawValue)",
                        snippet: response.text,
                        sourceDomain: intent.domains.first,
                        rawPayload: nil
                    )]
                    : response.citations

                for citation in citations.prefix(3) {
                    let combinedText = [citation.snippet, response.text]
                        .compactMap { value in
                            guard let value, !value.isEmpty else { return nil }
                            return value
                        }
                        .joined(separator: "\n")
                    let normalizedText = normalizeEvidenceText(combinedText)
                    let inferredKind = inferSourceKind(
                        from: citation.urlString,
                        fallback: intent.sourceKind
                    )
                    let validation = validateEvidence(
                        text: normalizedText,
                        company: company,
                        sourceKind: inferredKind,
                        requestedURLString: citation.urlString,
                        resolvedURLString: citation.urlString,
                        acquisitionMethod: .providerSearch,
                        fallbackTitle: citation.title
                    )

                    payloads.append(
                        makePayload(
                            title: citation.title,
                            urlString: citation.urlString,
                            resolvedURLString: citation.urlString,
                            sourceKind: validation.sourceKind,
                            acquisitionMethod: .providerSearch,
                            fetchStatus: validation.fetchStatus,
                            validationStatus: validation.validationStatus,
                            validationReason: validation.reason,
                            confidence: validation.confidence,
                            excerptText: normalizedText,
                            fetchedText: normalizedText,
                            errorMessage: nil,
                            citationPayload: citation.rawPayload,
                            orderIndex: nextIndex,
                            fetchedAt: fetchedAt
                        )
                    )
                    nextIndex += 1
                }
            } catch {
                let fallbackURL = siteRootURL(for: intent.domains.first) ?? "pipeline://search/\(intent.sourceKind.rawValue)"
                payloads.append(
                    makePayload(
                        title: intent.title,
                        urlString: fallbackURL,
                        resolvedURLString: nil,
                        sourceKind: intent.sourceKind,
                        acquisitionMethod: .providerSearch,
                        fetchStatus: .blocked,
                        validationStatus: .blocked,
                        validationReason: error.localizedDescription,
                        confidence: .low,
                        excerptText: nil,
                        fetchedText: nil,
                        errorMessage: error.localizedDescription,
                        citationPayload: nil,
                        orderIndex: nextIndex,
                        fetchedAt: fetchedAt
                    )
                )
                nextIndex += 1
            }
        }

        return payloads
    }

    private static func manualSourcePayload(
        company: CompanyProfile,
        orderIndex: Int
    ) -> CompanyResearchSourcePayload? {
        guard let notes = company.notesMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
              !notes.isEmpty else {
            return nil
        }

        let normalizedText = normalizeEvidenceText(notes)
        return makePayload(
            title: "Manual Research Notes",
            urlString: "pipeline://manual/company-notes",
            resolvedURLString: nil,
            sourceKind: .manual,
            acquisitionMethod: .manual,
            fetchStatus: .manual,
            validationStatus: .manual,
            validationReason: "User-authored company notes.",
            confidence: .medium,
            excerptText: normalizedText,
            fetchedText: normalizedText,
            errorMessage: nil,
            citationPayload: nil,
            orderIndex: orderIndex,
            fetchedAt: Date()
        )
    }

    private static func makePrompt(
        company: CompanyProfile,
        application: JobApplication?,
        sources: [CompanyResearchSourcePayload]
    ) -> String {
        var lines: [String] = [
            "Company: \(company.name)"
        ]

        if let application {
            lines.append("Role: \(application.role)")
            lines.append("Location: \(application.location)")
            if let compensation = application.expectedTotalCompRange ?? application.postedTotalCompRange {
                lines.append("Known Application Compensation: \(compensation)")
            }
        }

        let sourceBlocks = sources.map { source in
            var block = """
            Source \(source.orderIndex + 1): \(source.title)
            URL: \(source.resolvedURLString ?? source.urlString)
            Kind: \(source.sourceKind.rawValue)
            Acquisition: \(source.acquisitionMethod.rawValue)
            Validation: \(source.validationStatus.rawValue)
            """

            if let validationReason = source.validationReason {
                block += "\nValidation Notes: \(validationReason)"
            }
            if let fetchedText = source.fetchedText {
                block += "\nContent:\n\(fetchedText)"
            }
            return block
        }

        lines.append("Validated Evidence:\n\(sourceBlocks.joined(separator: "\n\n"))")
        return lines.joined(separator: "\n\n")
    }

    private static func parseResponse(
        _ rawText: String,
        usage: AIUsageMetrics?,
        sourcePayloads: [CompanyResearchSourcePayload]
    ) throws -> CompanyResearchResult {
        let cleaned = stripMarkdownFences(from: rawText)
        let candidateJSON = extractJSONObject(from: cleaned) ?? cleaned

        guard let data = candidateJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.parsingError("Company research response was not valid JSON.")
        }

        let sizeBand = (json["sizeBand"] as? String).flatMap { CompanySizeBand(rawValue: $0) }
            ?? (json["size_band"] as? String).flatMap { CompanySizeBand(rawValue: $0) }

        let salaryFindings = ((json["salaryFindings"] as? [[String: Any]])
            ?? (json["salary_findings"] as? [[String: Any]])
            ?? [])
            .compactMap { item -> CompanyResearchSalaryFinding? in
                let roleTitle = (item["roleTitle"] as? String)
                    ?? (item["title"] as? String)
                    ?? ""
                let location = (item["location"] as? String) ?? ""
                let sourceName = (item["sourceName"] as? String)
                    ?? (item["source"] as? String)
                    ?? "External Research"
                guard !roleTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return nil
                }

                let currency = Currency(rawValue: (item["currency"] as? String) ?? Currency.usd.rawValue) ?? .usd

                return CompanyResearchSalaryFinding(
                    roleTitle: roleTitle,
                    location: location,
                    sourceName: sourceName,
                    sourceURLString: item["sourceURL"] as? String ?? item["source_url"] as? String,
                    notes: item["notes"] as? String,
                    confidenceNotes: item["confidenceNotes"] as? String ?? item["confidence_notes"] as? String,
                    currency: currency,
                    minBaseCompensation: intValue(item["minBaseCompensation"] ?? item["min_base_compensation"]),
                    maxBaseCompensation: intValue(item["maxBaseCompensation"] ?? item["max_base_compensation"]),
                    minTotalCompensation: intValue(item["minTotalCompensation"] ?? item["min_total_compensation"]),
                    maxTotalCompensation: intValue(item["maxTotalCompensation"] ?? item["max_total_compensation"])
                )
            }

        let summary = json["summary"] as? String
            ?? json["companySummary"] as? String
            ?? json["company_summary"] as? String
        let summaryConfidenceNote = json["summaryConfidenceNote"] as? String
            ?? json["summary_confidence_note"] as? String
        let enrichedSummaryConfidence = summaryConfidenceNote ?? confidenceNote(for: sourcePayloads)
        let runStatus = runStatus(for: sourcePayloads, summary: summary)

        return CompanyResearchResult(
            websiteURL: bestURL(
                parsedURL: json["websiteURL"] as? String ?? json["website_url"] as? String,
                sourceKind: .companyWebsite,
                sourcePayloads: sourcePayloads
            ),
            linkedInURL: bestURL(
                parsedURL: json["linkedInURL"] as? String ?? json["linkedin_url"] as? String,
                sourceKind: .linkedIn,
                sourcePayloads: sourcePayloads
            ),
            glassdoorURL: bestURL(
                parsedURL: json["glassdoorURL"] as? String ?? json["glassdoor_url"] as? String,
                sourceKind: .glassdoor,
                sourcePayloads: sourcePayloads
            ),
            levelsFYIURL: bestURL(
                parsedURL: json["levelsFYIURL"] as? String ?? json["levels_fyi_url"] as? String,
                sourceKind: .levelsFYI,
                sourcePayloads: sourcePayloads
            ),
            teamBlindURL: bestURL(
                parsedURL: json["teamBlindURL"] as? String ?? json["teamblind_url"] as? String,
                sourceKind: .teamBlind,
                sourcePayloads: sourcePayloads
            ),
            industry: json["industry"] as? String,
            sizeBand: sizeBand,
            headquarters: json["headquarters"] as? String,
            summary: summary,
            summaryConfidenceNote: enrichedSummaryConfidence,
            runStatus: runStatus,
            failureMessage: runStatus == .failed ? "No verified evidence was available for this company." : nil,
            sources: sourcePayloads,
            salaryFindings: salaryFindings,
            usage: usage,
            rawResponseText: rawText
        )
    }

    static func validateEvidence(
        text: String,
        company: CompanyProfile,
        sourceKind: CompanyResearchSourceKind,
        requestedURLString: String,
        resolvedURLString: String?,
        acquisitionMethod: ResearchAcquisitionMethod,
        fallbackTitle: String
    ) -> (
        sourceKind: CompanyResearchSourceKind,
        fetchStatus: CompanyResearchFetchStatus,
        validationStatus: ResearchValidationStatus,
        reason: String?,
        confidence: ResearchConfidence
    ) {
        let effectiveURL = resolvedURLString ?? requestedURLString
        let inferredKind = inferSourceKind(from: effectiveURL, fallback: sourceKind)
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedText = normalizedText.lowercased()
        let host = URL(string: effectiveURL)?.host?.lowercased() ?? ""
        let companyName = company.name.lowercased()

        if inferredKind == .manual {
            return (inferredKind, .manual, .manual, "User-authored manual note.", .medium)
        }

        if looksLikeSearchInterstitial(urlString: effectiveURL, text: lowercasedText) {
            return (inferredKind, .invalid, .invalid, "Search results or redirect page, not a usable source page.", .low)
        }

        if looksBlocked(host: host, text: lowercasedText) {
            return (inferredKind, .blocked, .blocked, "The source appears blocked, gated, or anti-bot protected.", .low)
        }

        if normalizedText.count < 80 {
            return (inferredKind, .invalid, .invalid, "The page did not contain enough readable text to trust.", .low)
        }

        let mentionsCompany = lowercasedText.contains(companyName)
        let domainMatchesCompany = domainMatchesCompanyWebsite(host: host, company: company)
        let thinThreshold = acquisitionMethod == .providerSearch ? 140 : 220

        if inferredKind == .companyWebsite && !domainMatchesCompany && !mentionsCompany {
            return (inferredKind, .partial, .partial, "The source is readable but could not be strongly linked to the company.", .low)
        }

        if inferredKind != .companyWebsite && !mentionsCompany && normalizedText.count < thinThreshold {
            return (inferredKind, .invalid, .invalid, "\(fallbackTitle) did not include enough company-specific content.", .low)
        }

        if normalizedText.count < thinThreshold {
            return (inferredKind, .partial, .partial, "The source is readable but thin; summary confidence is reduced.", .low)
        }

        if acquisitionMethod == .providerSearch && !mentionsCompany {
            return (inferredKind, .partial, .partial, "The citation is relevant but only weakly tied to the company name.", .medium)
        }

        let confidence: ResearchConfidence = (inferredKind == .companyWebsite || domainMatchesCompany) ? .high : .medium
        return (inferredKind, .verified, .verified, "Validated company-specific evidence.", confidence)
    }

    static func looksLikeSearchInterstitial(urlString: String, text: String) -> Bool {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        let path = URL(string: urlString)?.path.lowercased() ?? ""
        if host.contains("google.") && path.contains("/search") {
            return true
        }
        if host.contains("bing.") && path.contains("/search") {
            return true
        }

        let markers = [
            "please click here if you are not redirected within a few seconds",
            "google search",
            "send feedback",
            "unusual traffic from your computer network"
        ]
        return markers.contains(where: text.contains)
    }

    static func looksBlocked(host: String, text: String) -> Bool {
        let generalMarkers = [
            "access denied",
            "captcha",
            "verify you are human",
            "security check",
            "temporarily unavailable",
            "sign in to continue"
        ]
        if generalMarkers.contains(where: text.contains) {
            return true
        }

        if host.contains("linkedin.com") {
            let linkedInMarkers = [
                "join linkedin",
                "sign in to view more",
                "linkedin login"
            ]
            return linkedInMarkers.contains(where: text.contains)
        }

        if host.contains("glassdoor.com") || host.contains("teamblind.com") {
            let gatedMarkers = [
                "continue to glassdoor",
                "sign in to continue",
                "please create an account"
            ]
            return gatedMarkers.contains(where: text.contains)
        }

        return false
    }

    private static func domainMatchesCompanyWebsite(host: String, company: CompanyProfile) -> Bool {
        guard let websiteURL = company.websiteURL,
              let companyDomain = URLHelpers.extractDomain(from: websiteURL)?.lowercased(),
              !host.isEmpty else {
            return false
        }
        return host.contains(companyDomain)
    }

    static func inferSourceKind(
        from urlString: String,
        fallback: CompanyResearchSourceKind
    ) -> CompanyResearchSourceKind {
        let host = URL(string: urlString)?.host?.lowercased() ?? ""
        if host.contains("linkedin.com") {
            return .linkedIn
        }
        if host.contains("glassdoor.com") {
            return .glassdoor
        }
        if host.contains("levels.fyi") {
            return .levelsFYI
        }
        if host.contains("teamblind.com") {
            return .teamBlind
        }
        return fallback
    }

    static func normalizeEvidenceText(_ text: String) -> String {
        var normalized = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.count > 5000 {
            normalized = String(normalized.prefix(5000))
        }
        return normalized
    }

    private static func blockedFetchStatus(for error: Error) -> CompanyResearchFetchStatus {
        let description = error.localizedDescription.lowercased()
        if description.contains("http 999") || description.contains("rate limited") || description.contains("unauthorized") {
            return .blocked
        }
        return .failed
    }

    private static func blockedValidationStatus(for error: Error) -> ResearchValidationStatus {
        let description = error.localizedDescription.lowercased()
        if description.contains("http 999") || description.contains("rate limited") || description.contains("unauthorized") {
            return .blocked
        }
        return .invalid
    }

    private static func makePayload(
        title: String,
        urlString: String,
        resolvedURLString: String?,
        sourceKind: CompanyResearchSourceKind,
        acquisitionMethod: ResearchAcquisitionMethod,
        fetchStatus: CompanyResearchFetchStatus,
        validationStatus: ResearchValidationStatus,
        validationReason: String?,
        confidence: ResearchConfidence?,
        excerptText: String?,
        fetchedText: String?,
        errorMessage: String?,
        citationPayload: String?,
        orderIndex: Int,
        fetchedAt: Date
    ) -> CompanyResearchSourcePayload {
        let excerpt = excerptText.map { String($0.prefix(500)) }
        return CompanyResearchSourcePayload(
            title: title,
            urlString: urlString,
            sourceKind: sourceKind,
            fetchStatus: fetchStatus,
            contentExcerpt: excerpt,
            fetchedText: fetchedText,
            errorMessage: errorMessage,
            orderIndex: orderIndex,
            resolvedURLString: resolvedURLString,
            validationStatus: validationStatus,
            acquisitionMethod: acquisitionMethod,
            validationReason: validationReason,
            confidence: confidence,
            citationPayload: citationPayload,
            fetchedAt: fetchedAt,
            validatedAt: fetchedAt
        )
    }

    private static func deduplicateSourcePayloads(
        _ payloads: [CompanyResearchSourcePayload]
    ) -> [CompanyResearchSourcePayload] {
        var bestByURL: [String: CompanyResearchSourcePayload] = [:]

        for payload in payloads {
            let key = (payload.resolvedURLString ?? payload.urlString).lowercased()
            guard !key.isEmpty else { continue }

            if let existing = bestByURL[key] {
                if score(payload) > score(existing) {
                    bestByURL[key] = payload
                }
            } else {
                bestByURL[key] = payload
            }
        }

        return bestByURL.values.sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        }
    }

    private static func score(_ payload: CompanyResearchSourcePayload) -> Int {
        let statusScore: Int
        switch payload.validationStatus {
        case .verified:
            statusScore = 5
        case .manual:
            statusScore = 4
        case .partial:
            statusScore = 3
        case .blocked:
            statusScore = 2
        case .invalid:
            statusScore = 1
        case .skipped:
            statusScore = 0
        }

        let confidenceScore: Int
        switch payload.confidence {
        case .high:
            confidenceScore = 3
        case .medium:
            confidenceScore = 2
        case .low:
            confidenceScore = 1
        case nil:
            confidenceScore = 0
        }

        return statusScore * 10 + confidenceScore
    }

    static func runStatus(
        for sourcePayloads: [CompanyResearchSourcePayload],
        summary: String?
    ) -> ResearchRunStatus {
        let hasVerified = sourcePayloads.contains { $0.validationStatus == .verified || $0.validationStatus == .manual }
        let hasAnyProblem = sourcePayloads.contains {
            $0.validationStatus == .blocked || $0.validationStatus == .invalid || $0.validationStatus == .partial
        }
        let hasSummary = summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false

        if !hasVerified || !hasSummary {
            return .failed
        }
        return hasAnyProblem ? .partial : .succeeded
    }

    private static func confidenceNote(for sourcePayloads: [CompanyResearchSourcePayload]) -> String {
        let verifiedCount = sourcePayloads.filter { $0.validationStatus == .verified || $0.validationStatus == .manual }.count
        let partialCount = sourcePayloads.filter { $0.validationStatus == .partial }.count

        if verifiedCount >= 3 {
            return "Built from multiple validated sources."
        }
        if verifiedCount >= 1 && partialCount > 0 {
            return "Built from limited verified evidence with some blocked or thin sources."
        }
        if verifiedCount >= 1 {
            return "Built from a narrow source set. Treat details as directional."
        }
        return "No validated source content was available."
    }

    private static func bestURL(
        parsedURL: String?,
        sourceKind: CompanyResearchSourceKind,
        sourcePayloads: [CompanyResearchSourcePayload]
    ) -> String? {
        CompanyProfile.normalizedURLString(parsedURL)
            ?? verifiedSourceURL(of: sourceKind, in: sourcePayloads)
    }

    private static func verifiedSourceURL(
        of sourceKind: CompanyResearchSourceKind,
        in sourcePayloads: [CompanyResearchSourcePayload]
    ) -> String? {
        sourcePayloads.first(where: {
            $0.sourceKind == sourceKind &&
            ($0.validationStatus == .verified || $0.validationStatus == .partial)
        }).map { $0.resolvedURLString ?? $0.urlString }
    }

    private static func siteRootURL(for domain: String?) -> String? {
        guard let domain, !domain.isEmpty else { return nil }
        return "https://www.\(domain)"
    }

    private static func stripMarkdownFences(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: #"^```[a-zA-Z0-9_-]*\s*"#, with: "", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: #"\s*```$"#, with: "", options: .regularExpression)
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
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
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

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as Int:
            return value
        case let value as Double:
            return Int(value.rounded())
        case let value as NSNumber:
            return value.intValue
        case let value as String:
            return Int(value.replacingOccurrences(of: ",", with: ""))
        default:
            return nil
        }
    }

    private static let providerSearchSystemPrompt = """
    Search the web for cited company evidence. Prefer official company pages and trustworthy platform pages. Return concise evidence with citations.
    """

    private static let systemPrompt = """
    You are an assistant that prepares structured company research for a job search workspace.

    Return exactly one JSON object with this schema:
    {
      "websiteURL": string | null,
      "linkedInURL": string | null,
      "glassdoorURL": string | null,
      "levelsFYIURL": string | null,
      "teamBlindURL": string | null,
      "industry": string | null,
      "sizeBand": "startup" | "small" | "midsize" | "enterprise" | null,
      "headquarters": string | null,
      "summary": string | null,
      "summaryConfidenceNote": string | null,
      "salaryFindings": [
        {
          "roleTitle": string,
          "location": string,
          "sourceName": string,
          "sourceURL": string | null,
          "currency": string,
          "minBaseCompensation": number | null,
          "maxBaseCompensation": number | null,
          "minTotalCompensation": number | null,
          "maxTotalCompensation": number | null,
          "notes": string | null,
          "confidenceNotes": string | null
        }
      ]
    }

    Rules:
    - Use only the provided validated evidence. If a field is unknown, return null.
    - Every summary claim must be supported by the supplied evidence.
    - Summary should be 120-220 words and explicitly mention uncertainty when the evidence is thin.
    - Salary findings should only be included when the evidence clearly supports the range.
    - Preserve source URLs exactly when present in the evidence.
    - Do not invent Glassdoor, Levels.fyi, TeamBlind, or LinkedIn URLs unless they are clearly present in the evidence.
    - Output raw JSON only.
    """
}

private extension Array {
    func uniquedPreservingOrder<T: Hashable>(by key: KeyPath<Element, T>) -> [Element] {
        var seen: Set<T> = []
        var result: [Element] = []

        for item in self {
            let value = item[keyPath: key]
            if seen.insert(value).inserted {
                result.append(item)
            }
        }

        return result
    }
}
