import Foundation
import SwiftData
import Testing
@testable import PipelineKit

@MainActor
@Test func offerComparisonWorksheetSeedsFromOfferedApplications() throws {
    let container = try makeOfferComparisonContainer()
    let context = ModelContext(container)

    let offeredA = JobApplication(
        companyName: "Google",
        role: "Senior Engineer",
        location: "Mountain View",
        status: .offered
    )
    let offeredB = JobApplication(
        companyName: "Stripe",
        role: "Engineer",
        location: "Remote",
        status: .offered
    )
    let applied = JobApplication(
        companyName: "Startup X",
        role: "Engineer",
        location: "Remote",
        status: .applied
    )

    context.insert(offeredA)
    context.insert(offeredB)
    context.insert(applied)
    try context.save()

    let service = OfferComparisonWorksheetService()
    let worksheet = try service.loadOrCreateWorksheet(
        in: context,
        offeredApplications: [offeredA, offeredB]
    )

    #expect(worksheet.selectedApplicationIDs == [offeredA.id, offeredB.id])
    #expect(worksheet.knownApplicationIDs == [offeredA.id, offeredB.id])
    #expect(worksheet.sortedFactors.count == OfferComparisonFactorKind.builtInCases.count)
}

@Test func offerComparisonScoringRequiresCompleteScores() {
    let first = JobApplication(
        companyName: "Google",
        role: "Senior Engineer",
        location: "Mountain View",
        status: .offered
    )
    let second = JobApplication(
        companyName: "Stripe",
        role: "Engineer",
        location: "Remote",
        status: .offered
    )

    let worksheet = OfferComparisonWorksheet(
        selectedApplicationIDs: [first.id, second.id],
        knownApplicationIDs: [first.id, second.id]
    )
    let factor = OfferComparisonFactor(kind: .baseSalary, weight: 3, sortOrder: 0, worksheet: worksheet)
    worksheet.factors = [factor]
    _ = factor.upsertValue(applicationID: first.id, displayText: nil, score: 5)

    let scoringService = OfferComparisonScoringService()
    let incomplete = scoringService.evaluate(worksheet: worksheet, applications: [first, second])

    #expect(incomplete.isComplete == false)
    #expect(incomplete.missingScoreCount == 1)

    _ = factor.upsertValue(applicationID: second.id, displayText: nil, score: 3)
    let complete = scoringService.evaluate(worksheet: worksheet, applications: [first, second])

    #expect(complete.isComplete == true)
    #expect(complete.results.first?.applicationID == first.id)
}

@Test func offerComparisonYearOneCompUsesAnnualizedEquity() {
    let application = JobApplication(
        companyName: "Google",
        role: "Senior Engineer",
        location: "Mountain View",
        status: .offered,
        currency: .usd,
        offerBaseCompensation: 220_000,
        offerBonusCompensation: 50_000,
        offerEquityCompensation: 400_000
    )

    #expect(application.offerEquityYearOneCompensation == 100_000)
    #expect(application.offerYearOneTotalComp == 370_000)
    #expect(application.offerTotalComp == 370_000)
}

@MainActor
@Test func offerComparisonCustomFactorPersistsValuesAndSelectionChanges() throws {
    let container = try makeOfferComparisonContainer()
    let context = ModelContext(container)

    let first = JobApplication(
        companyName: "Google",
        role: "Senior Engineer",
        location: "Mountain View",
        status: .offered
    )
    let second = JobApplication(
        companyName: "Stripe",
        role: "Engineer",
        location: "Remote",
        status: .offered
    )

    context.insert(first)
    context.insert(second)
    try context.save()

    let service = OfferComparisonWorksheetService()
    let worksheet = try service.loadOrCreateWorksheet(in: context, offeredApplications: [first, second])
    let factor = try service.addCustomFactor(titled: "Visa Sponsorship", to: worksheet, context: context)

    try service.upsertValue(
        for: factor,
        applicationID: first.id,
        displayText: "Available",
        score: 5,
        context: context
    )
    try service.setSelection(applicationID: second.id, isSelected: false, on: worksheet, context: context)

    #expect(worksheet.selectedApplicationIDs == [first.id])
    #expect(factor.value(for: first.id)?.displayText == "Available")
    #expect(factor.value(for: first.id)?.score == 5)
}

private func makeOfferComparisonContainer() throws -> ModelContainer {
    let schema = Schema([
        JobApplication.self,
        OfferComparisonWorksheet.self,
        OfferComparisonFactor.self,
        OfferComparisonValue.self
    ])
    let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [configuration])
}
