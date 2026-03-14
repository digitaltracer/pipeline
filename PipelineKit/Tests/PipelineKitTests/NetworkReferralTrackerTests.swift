import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@Test @MainActor func linkedInCSVImportCreatesAndUpdatesNetworkRows() throws {
    let container = try makeNetworkReferralContainer()
    let context = ModelContext(container)

    let csv = """
    First Name,Last Name,Email Address,Company,Position,URL,Connected On
    Sarah,Chen,sarah@example.com,Google,Staff Engineer,https://www.linkedin.com/in/sarah-chen,01/10/2024
    """

    let firstResult = try LinkedInCSVImportService.shared.importCSVString(
        csv,
        sourceFileName: "connections.csv",
        into: context
    )

    #expect(firstResult.importedCount == 1)
    #expect(firstResult.updatedCount == 0)

    let updatedCSV = """
    First Name,Last Name,Email Address,Company,Position,URL,Connected On
    Sarah,Chen,sarah@example.com,Google LLC,Principal Engineer,https://www.linkedin.com/in/sarah-chen,01/10/2024
    """

    let secondResult = try LinkedInCSVImportService.shared.importCSVString(
        updatedCSV,
        sourceFileName: "connections-2.csv",
        into: context
    )

    let connections = try context.fetch(FetchDescriptor<ImportedNetworkConnection>())

    #expect(secondResult.importedCount == 0)
    #expect(secondResult.updatedCount == 1)
    #expect(connections.count == 1)
    #expect(connections.first?.title == "Principal Engineer")
    #expect(connections.first?.companyName == "Google LLC")
}

@Test @MainActor func linkedInCSVImportRejectsMissingLinkedInHeaders() throws {
    let container = try makeNetworkReferralContainer()
    let context = ModelContext(container)

    let csv = """
    Name,Email,Company
    Sarah Chen,sarah@example.com,Google
    """

    #expect(throws: LinkedInCSVImportError.self) {
        try LinkedInCSVImportService.shared.importCSVString(
            csv,
            sourceFileName: "bad.csv",
            into: context
        )
    }
}

@Test @MainActor func networkReferralMatchingUsesConfirmedAliases() throws {
    let container = try makeNetworkReferralContainer()
    let context = ModelContext(container)

    let application = JobApplication(
        companyName: "Google",
        role: "iOS Engineer",
        location: "Remote"
    )
    let connection = ImportedNetworkConnection(
        providerRowID: "alphabet-sarah",
        fullName: "Sarah Chen",
        email: "sarah@example.com",
        companyName: "Alphabet",
        title: "Staff Engineer"
    )

    context.insert(application)
    context.insert(connection)
    try context.save()

    let noAliasSuggestions = try NetworkReferralMatchingService.suggestions(for: application, in: context)
    #expect(noAliasSuggestions.isEmpty)

    _ = try NetworkReferralMatchingService.addAlias(
        canonicalName: "Google",
        aliasName: "Alphabet",
        in: context
    )

    let aliasSuggestions = try NetworkReferralMatchingService.suggestions(for: application, in: context)
    #expect(aliasSuggestions.count == 1)
    #expect(aliasSuggestions.first?.matchedViaAlias == true)
}

@Test func dashboardAnalyticsCountsReceivedReferralAttribution() async throws {
    let application = JobApplication(
        companyName: "OpenAI",
        role: "Product Engineer",
        location: "San Francisco",
        status: .interviewing
    )
    let referredApplication = JobApplication(
        companyName: "Google",
        role: "iOS Engineer",
        location: "Remote",
        status: .interviewing
    )
    let referralAttempt = ReferralAttempt(
        status: .received,
        askedAt: Date(),
        application: referredApplication
    )
    referredApplication.addReferralAttempt(referralAttempt)

    let analytics = await DashboardAnalyticsService(
        exchangeRateService: LocalMockExchangeRateProvider(rate: 1.0)
    ).analyze(
        applications: [application, referredApplication],
        cycles: [],
        goals: [],
        scope: .thisMonth,
        baseCurrency: .usd,
        referenceDate: Date()
    )

    #expect(analytics.referralSummary.applicationsWithReceivedReferral == 1)
    #expect(analytics.referralSummary.interviewingApplicationsWithReferral == 1)
    #expect(analytics.referralSummary.receivedReferralAttempts == 1)
    #expect(analytics.referralSummary.interviewReferralRate == 0.5)
}

private func makeNetworkReferralContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        Contact.self,
        ApplicationContactLink.self,
        ApplicationActivity.self,
        NetworkImportBatch.self,
        ImportedNetworkConnection.self,
        CompanyAlias.self,
        ReferralAttempt.self
    ])

    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}

private struct LocalMockExchangeRateProvider: ExchangeRateProviding {
    let rate: Double

    func convert(amount: Int, from: Currency, to: Currency, on date: Date) async -> ExchangeRateService.ConversionResult? {
        ExchangeRateService.ConversionResult(amount: Double(amount) * rate, rateDate: date, usedFallback: false)
    }
}
