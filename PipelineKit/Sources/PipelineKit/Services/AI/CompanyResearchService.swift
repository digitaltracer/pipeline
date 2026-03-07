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

    public init(
        title: String,
        urlString: String,
        sourceKind: CompanyResearchSourceKind,
        fetchStatus: CompanyResearchFetchStatus,
        contentExcerpt: String?,
        fetchedText: String?,
        errorMessage: String?,
        orderIndex: Int
    ) {
        self.title = title
        self.urlString = urlString
        self.sourceKind = sourceKind
        self.fetchStatus = fetchStatus
        self.contentExcerpt = contentExcerpt
        self.fetchedText = fetchedText
        self.errorMessage = errorMessage
        self.orderIndex = orderIndex
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
        self.sources = sources
        self.salaryFindings = salaryFindings
        self.usage = usage
        self.rawResponseText = rawResponseText
    }
}

public enum CompanyResearchService {
    private struct CandidateSource: Sendable {
        let title: String
        let urlString: String
        let sourceKind: CompanyResearchSourceKind
    }

    public static func generateResearch(
        provider: AIProvider,
        apiKey: String,
        model: String,
        company: CompanyProfile,
        application: JobApplication? = nil,
        webContentProvider: WebContentProvider = BasicWebContentProvider(serviceName: "CompanyResearch")
    ) async throws -> CompanyResearchResult {
        let candidates = candidateSources(company: company, application: application)
        let collectedSources = await collectSourcePayloads(from: candidates, via: webContentProvider)
        let prompt = makePrompt(company: company, application: application, sources: collectedSources)

        let response = try await AICompletionClient.completeWithUsage(
            provider: provider,
            apiKey: apiKey,
            model: model,
            systemPrompt: systemPrompt,
            userPrompt: prompt,
            maxTokens: 3500,
            temperature: 0.2
        )

        return try parseResponse(
            response.text,
            usage: response.usage,
            sourcePayloads: collectedSources
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
            summaryText: result.summary,
            rawResponseText: result.rawResponseText,
            errorMessage: errorMessage,
            startedAt: startedAt,
            finishedAt: finishedAt,
            applicationID: applicationID,
            company: company
        )
        modelContext.insert(snapshot)

        for sourcePayload in result.sources {
            let source = CompanyResearchSource(
                title: sourcePayload.title,
                urlString: sourcePayload.urlString,
                sourceKind: sourcePayload.sourceKind,
                fetchStatus: sourcePayload.fetchStatus,
                contentExcerpt: sourcePayload.contentExcerpt,
                errorMessage: sourcePayload.errorMessage,
                orderIndex: sourcePayload.orderIndex,
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

    private static func candidateSources(company: CompanyProfile, application: JobApplication?) -> [CandidateSource] {
        var sources: [CandidateSource] = []

        func append(_ title: String, _ urlString: String?, _ kind: CompanyResearchSourceKind) {
            guard let normalizedURL = CompanyProfile.normalizedURLString(urlString) else { return }
            sources.append(CandidateSource(title: title, urlString: normalizedURL, sourceKind: kind))
        }

        append("Company Website", company.websiteURL, .companyWebsite)
        append("Job Posting", application?.jobURL, .jobPosting)
        append("LinkedIn", company.linkedInURL ?? URLHelpers.linkedInCompanyURL(companyName: company.name)?.absoluteString, .linkedIn)
        append("Glassdoor", company.glassdoorURL, .glassdoor)
        append("Levels.fyi", company.levelsFYIURL, .levelsFYI)
        append("TeamBlind", company.teamBlindURL, .teamBlind)

        if let searchURL = googleSearchURL(
            companyName: company.name,
            role: application?.role,
            location: application?.location,
            site: nil
        ) {
            append("Company Search", searchURL.absoluteString, .search)
        }

        if let levelsSearch = googleSearchURL(
            companyName: company.name,
            role: application?.role,
            location: application?.location,
            site: "levels.fyi"
        ) {
            append("Levels.fyi Search", levelsSearch.absoluteString, .search)
        }

        if let blindSearch = googleSearchURL(
            companyName: company.name,
            role: application?.role,
            location: application?.location,
            site: "teamblind.com"
        ) {
            append("TeamBlind Search", blindSearch.absoluteString, .search)
        }

        if let glassdoorSearch = googleSearchURL(
            companyName: company.name,
            role: application?.role,
            location: application?.location,
            site: "glassdoor.com"
        ) {
            append("Glassdoor Search", glassdoorSearch.absoluteString, .search)
        }

        return sources.uniquedPreservingOrder(by: \.urlString).prefix(8).map { $0 }
    }

    private static func collectSourcePayloads(
        from candidates: [CandidateSource],
        via provider: WebContentProvider
    ) async -> [CompanyResearchSourcePayload] {
        var payloads: [CompanyResearchSourcePayload] = []

        for (index, candidate) in candidates.enumerated() {
            do {
                let text = try await provider.fetchText(from: candidate.urlString)
                let excerpt = String(text.prefix(500))
                payloads.append(
                    CompanyResearchSourcePayload(
                        title: candidate.title,
                        urlString: candidate.urlString,
                        sourceKind: candidate.sourceKind,
                        fetchStatus: .fetched,
                        contentExcerpt: excerpt,
                        fetchedText: String(text.prefix(5000)),
                        errorMessage: nil,
                        orderIndex: index
                    )
                )
            } catch {
                payloads.append(
                    CompanyResearchSourcePayload(
                        title: candidate.title,
                        urlString: candidate.urlString,
                        sourceKind: candidate.sourceKind,
                        fetchStatus: .failed,
                        contentExcerpt: nil,
                        fetchedText: nil,
                        errorMessage: error.localizedDescription,
                        orderIndex: index
                    )
                )
            }
        }

        return payloads
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

        if let notes = company.notesMarkdown, !notes.isEmpty {
            lines.append("User Notes:\n\(notes)")
        }

        let sourceBlocks = sources.map { source in
            var block = """
            Source \(source.orderIndex + 1): \(source.title)
            URL: \(source.urlString)
            Kind: \(source.sourceKind.rawValue)
            Status: \(source.fetchStatus.rawValue)
            """

            if let errorMessage = source.errorMessage {
                block += "\nError: \(errorMessage)"
            }
            if let fetchedText = source.fetchedText {
                block += "\nContent:\n\(fetchedText)"
            }
            return block
        }

        lines.append("Sources:\n\(sourceBlocks.joined(separator: "\n\n"))")
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

        return CompanyResearchResult(
            websiteURL: json["websiteURL"] as? String ?? json["website_url"] as? String,
            linkedInURL: json["linkedInURL"] as? String ?? json["linkedin_url"] as? String,
            glassdoorURL: json["glassdoorURL"] as? String ?? json["glassdoor_url"] as? String,
            levelsFYIURL: json["levelsFYIURL"] as? String ?? json["levels_fyi_url"] as? String,
            teamBlindURL: json["teamBlindURL"] as? String ?? json["teamblind_url"] as? String,
            industry: json["industry"] as? String,
            sizeBand: sizeBand,
            headquarters: json["headquarters"] as? String,
            summary: json["summary"] as? String ?? json["companySummary"] as? String ?? json["company_summary"] as? String,
            sources: sourcePayloads,
            salaryFindings: salaryFindings,
            usage: usage,
            rawResponseText: rawText
        )
    }

    private static func googleSearchURL(
        companyName: String,
        role: String?,
        location: String?,
        site: String?
    ) -> URL? {
        var query = companyName
        if let role, !role.isEmpty {
            query += " \(role)"
        }
        if let location, !location.isEmpty {
            query += " \(location)"
        }
        if let site, !site.isEmpty {
            query += " site:\(site)"
        }

        guard let escaped = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return URL(string: "https://www.google.com/search?q=\(escaped)")
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
    - Use only the provided source text. If a field is unknown, return null.
    - Summary should be 120-220 words and mention source uncertainty when evidence is thin.
    - Salary findings should only be included when the source text supports the range.
    - Preserve source URLs exactly when present in the source list.
    - Do not invent Glassdoor, Levels.fyi, TeamBlind, or LinkedIn URLs unless they are clearly present in the provided content or source list.
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
