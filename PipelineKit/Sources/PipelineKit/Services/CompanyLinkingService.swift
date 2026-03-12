import Foundation
import SwiftData

public enum CompanyLinkingService {
    @discardableResult
    public static func ensureCompanyLinked(
        for application: JobApplication,
        in modelContext: ModelContext
    ) throws -> CompanyProfile {
        let normalizedCompanyName = CompanyProfile.normalizedName(from: application.companyName)
        if let existing = application.company,
           existing.normalizedName == normalizedCompanyName,
           !normalizedCompanyName.isEmpty {
            hydrateCompany(existing, from: application)
            return existing
        }

        let company = try existingCompany(
            normalizedName: normalizedCompanyName,
            in: modelContext
        ) ?? createCompany(for: application, normalizedName: normalizedCompanyName, in: modelContext)

        company.rename(application.companyName)
        hydrateCompany(company, from: application)
        application.assignCompany(company)
        return company
    }

    @discardableResult
    public static func backfillApplicationsIfNeeded(in modelContext: ModelContext) throws -> Int {
        let applications = try modelContext.fetch(FetchDescriptor<JobApplication>())
        var linkedCount = 0

        for application in applications {
            let normalizedCompanyName = CompanyProfile.normalizedName(from: application.companyName)
            guard !normalizedCompanyName.isEmpty else { continue }

            if let company = application.company,
               company.normalizedName == normalizedCompanyName {
                hydrateCompany(company, from: application)
                continue
            }

            _ = try ensureCompanyLinked(for: application, in: modelContext)
            linkedCount += 1
        }

        if linkedCount > 0 {
            try modelContext.save()
        }

        return linkedCount
    }

    public static func company(
        named companyName: String,
        in modelContext: ModelContext
    ) throws -> CompanyProfile? {
        let normalized = CompanyProfile.normalizedName(from: companyName)
        guard !normalized.isEmpty else { return nil }
        return try existingCompany(normalizedName: normalized, in: modelContext)
    }

    private static func existingCompany(
        normalizedName: String,
        in modelContext: ModelContext
    ) throws -> CompanyProfile? {
        let companies = try modelContext.fetch(FetchDescriptor<CompanyProfile>())
        return companies.first(where: { $0.normalizedName == normalizedName })
    }

    private static func createCompany(
        for application: JobApplication,
        normalizedName: String,
        in modelContext: ModelContext
    ) -> CompanyProfile {
        let company = CompanyProfile(
            name: application.companyName,
            websiteURL: inferredWebsiteURL(for: application)
        )
        company.normalizedName = normalizedName
        modelContext.insert(company)
        return company
    }

    private static func hydrateCompany(_ company: CompanyProfile, from application: JobApplication) {
        if company.websiteURL == nil {
            company.websiteURL = inferredWebsiteURL(for: application)
        }
        company.updateTimestamp()
    }

    private static func inferredWebsiteURL(for application: JobApplication) -> String? {
        if let domain = application.jobURL.flatMap({ URLHelpers.extractCompanyDomain(from: $0) }) {
            return CompanyProfile.normalizedURLString("https://\(domain)")
        }

        if let domain = application.companyDomain {
            return CompanyProfile.normalizedURLString("https://\(domain)")
        }

        return nil
    }
}
