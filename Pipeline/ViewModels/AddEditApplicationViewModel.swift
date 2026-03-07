import Foundation
import SwiftData
import SwiftUI
import PipelineKit

@Observable
final class AddEditApplicationViewModel {
    enum SaveError: LocalizedError {
        case validationFailed([String])

        var errorDescription: String? {
            switch self {
            case .validationFailed(let errors):
                if let first = errors.first {
                    return first
                }
                return "Please fix validation errors before saving."
            }
        }
    }

    // Form fields
    var companyName: String = ""
    var role: String = ""
    var location: String = ""
    var jobURL: String = ""
    var jobDescription: String = ""
    var status: ApplicationStatus = .saved
    var priority: Priority = .medium
    var source: Source = .jobPortal
    var platform: Platform = .other
    var interviewStage: InterviewStage?
    var currency: Currency = .usd
    var salaryMinString: String = ""
    var salaryMaxString: String = ""
    var postedBonusString: String = ""
    var postedEquityString: String = ""
    var expectedSalaryMinString: String = ""
    var expectedSalaryMaxString: String = ""
    var expectedBonusString: String = ""
    var expectedEquityString: String = ""
    var offerBaseString: String = ""
    var offerBonusString: String = ""
    var offerEquityString: String = ""
    var selectedCycleID: UUID?
    var showExpectedCompensation = false
    var showOfferCompensation = false
    var appliedDate: Date?
    var hasAppliedDate: Bool = false
    var nextFollowUpDate: Date?
    var hasFollowUpDate: Bool = false

    // State
    var isEditing: Bool = false
    var editingApplication: JobApplication?

    // MARK: - Initialization

    init() {}

    init(application: JobApplication) {
        self.isEditing = true
        self.editingApplication = application
        loadFromApplication(application)
    }

    private func loadFromApplication(_ app: JobApplication) {
        companyName = app.companyName
        role = app.role
        location = app.location
        jobURL = app.jobURL ?? ""
        jobDescription = app.jobDescription ?? ""
        status = app.status
        priority = app.priority
        source = app.source
        platform = app.platform
        interviewStage = app.interviewStage
        currency = app.currency
        salaryMinString = app.salaryMin.map { String($0) } ?? ""
        salaryMaxString = app.salaryMax.map { String($0) } ?? ""
        postedBonusString = app.postedBonusCompensation.map { String($0) } ?? ""
        postedEquityString = app.postedEquityCompensation.map { String($0) } ?? ""
        expectedSalaryMinString = app.expectedSalaryMin.map { String($0) } ?? ""
        expectedSalaryMaxString = app.expectedSalaryMax.map { String($0) } ?? ""
        expectedBonusString = app.expectedBonusCompensation.map { String($0) } ?? ""
        expectedEquityString = app.expectedEquityCompensation.map { String($0) } ?? ""
        offerBaseString = app.offerBaseCompensation.map { String($0) } ?? ""
        offerBonusString = app.offerBonusCompensation.map { String($0) } ?? ""
        offerEquityString = app.offerEquityCompensation.map { String($0) } ?? ""
        selectedCycleID = app.cycle?.id
        showExpectedCompensation = app.hasExpectedCompensation
        showOfferCompensation = app.hasOfferCompensation
        appliedDate = app.appliedDate
        hasAppliedDate = app.appliedDate != nil
        nextFollowUpDate = app.nextFollowUpDate
        hasFollowUpDate = app.nextFollowUpDate != nil
    }

    // MARK: - Validation

    var isValid: Bool {
        validationErrors.isEmpty
    }

    var validationErrors: [String] {
        makeValidationErrors()
    }

    private func makeValidationErrors() -> [String] {
        var errors: [String] = []

        if companyName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Company name is required")
        }

        if role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Role is required")
        }

        if location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Location is required")
        }

        if !jobURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, normalizedJobURL == nil {
            errors.append("Invalid job URL")
        }

        if let min = salaryMin, let max = salaryMax, min > max {
            errors.append("Minimum salary cannot exceed maximum salary")
        }

        if let min = expectedSalaryMin, let max = expectedSalaryMax, min > max {
            errors.append("Expected minimum compensation cannot exceed expected maximum compensation")
        }

        return errors
    }

    // MARK: - Computed Properties

    var salaryMin: Int? {
        parseInteger(from: salaryMinString)
    }

    var salaryMax: Int? {
        parseInteger(from: salaryMaxString)
    }

    var postedBonus: Int? {
        parseInteger(from: postedBonusString)
    }

    var postedEquity: Int? {
        parseInteger(from: postedEquityString)
    }

    var expectedSalaryMin: Int? {
        parseInteger(from: expectedSalaryMinString)
    }

    var expectedSalaryMax: Int? {
        parseInteger(from: expectedSalaryMaxString)
    }

    var expectedBonus: Int? {
        parseInteger(from: expectedBonusString)
    }

    var expectedEquity: Int? {
        parseInteger(from: expectedEquityString)
    }

    var offerBase: Int? {
        parseInteger(from: offerBaseString)
    }

    var offerBonus: Int? {
        parseInteger(from: offerBonusString)
    }

    var offerEquity: Int? {
        parseInteger(from: offerEquityString)
    }

    var title: String {
        isEditing ? "Edit Application" : "Add Application"
    }

    private var normalizedJobURL: String? {
        let trimmed = jobURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let normalized = URLHelpers.normalize(trimmed)
        guard URLHelpers.isValidWebURL(normalized) else { return nil }
        return normalized
    }

    // MARK: - Actions

    func save(context: ModelContext) throws {
        guard isValid else { throw SaveError.validationFailed(validationErrors) }

        let savedApplication: JobApplication
        if isEditing, let app = editingApplication {
            try updateApplication(app, context: context)
            try context.save()
            savedApplication = app
        } else {
            let app = try createApplication(context: context)
            context.insert(app)
            try context.save()
            savedApplication = app
        }

        Task {
            @MainActor in
            await NotificationService.shared.syncFollowUpReminder(for: savedApplication)
        }
    }

    private func createApplication(context: ModelContext) throws -> JobApplication {
        let cycle = try resolvedCycle(context: context, shouldCreateDefault: true)
        let app = JobApplication(
            companyName: companyName.trimmingCharacters(in: .whitespacesAndNewlines),
            role: role.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
            jobURL: normalizedJobURL,
            jobDescription: jobDescription.isEmpty ? nil : jobDescription,
            status: status,
            priority: priority,
            source: source,
            platform: platform,
            interviewStage: interviewStage,
            currency: currency,
            salaryMin: salaryMin,
            salaryMax: salaryMax,
            postedBonusCompensation: postedBonus,
            postedEquityCompensation: postedEquity,
            expectedSalaryMin: expectedSalaryMin,
            expectedSalaryMax: expectedSalaryMax,
            expectedBonusCompensation: showExpectedCompensation ? expectedBonus : nil,
            expectedEquityCompensation: showExpectedCompensation ? expectedEquity : nil,
            offerBaseCompensation: showOfferCompensation ? offerBase : nil,
            offerBonusCompensation: showOfferCompensation ? offerBonus : nil,
            offerEquityCompensation: showOfferCompensation ? offerEquity : nil,
            appliedDate: hasAppliedDate ? appliedDate : nil,
            nextFollowUpDate: hasFollowUpDate ? nextFollowUpDate : nil,
            cycle: cycle
        )

        // Auto-detect platform from URL if not manually set
        if platform == .other, let normalizedJobURL {
            app.platform = Platform.detect(from: normalizedJobURL)
        }

        return app
    }

    private func updateApplication(_ app: JobApplication, context: ModelContext) throws {
        app.companyName = companyName.trimmingCharacters(in: .whitespacesAndNewlines)
        app.role = role.trimmingCharacters(in: .whitespacesAndNewlines)
        app.location = location.trimmingCharacters(in: .whitespacesAndNewlines)
        app.jobURL = normalizedJobURL
        app.jobDescription = jobDescription.isEmpty ? nil : jobDescription
        app.status = status
        app.priority = priority
        app.source = source
        app.platform = platform
        app.interviewStage = interviewStage
        app.currency = currency
        app.setSalaryRange(min: salaryMin, max: salaryMax)
        app.setPostedAdditionalCompensation(bonus: postedBonus, equity: postedEquity)
        app.setExpectedSalaryRange(
            min: showExpectedCompensation ? expectedSalaryMin : nil,
            max: showExpectedCompensation ? expectedSalaryMax : nil
        )
        app.setExpectedAdditionalCompensation(
            bonus: showExpectedCompensation ? expectedBonus : nil,
            equity: showExpectedCompensation ? expectedEquity : nil
        )
        app.setOfferCompensation(
            base: showOfferCompensation ? offerBase : nil,
            bonus: showOfferCompensation ? offerBonus : nil,
            equity: showOfferCompensation ? offerEquity : nil
        )
        app.appliedDate = hasAppliedDate ? appliedDate : nil
        app.nextFollowUpDate = hasFollowUpDate ? nextFollowUpDate : nil
        app.assignCycle(try resolvedCycle(context: context, shouldCreateDefault: false))
        app.updateTimestamp()

        // Auto-detect platform from URL if set to other
        if platform == .other, let normalizedJobURL {
            app.platform = Platform.detect(from: normalizedJobURL)
        }
    }

    // MARK: - URL Changed Handler

    func onJobURLChanged() {
        guard let normalizedJobURL else { return }

        // Auto-detect platform
        let detectedPlatform = Platform.detect(from: normalizedJobURL)
        if detectedPlatform != .other {
            platform = detectedPlatform
        }
    }

    func ensureDefaultCycleSelection(from cycles: [JobSearchCycle]) {
        guard selectedCycleID == nil else { return }
        selectedCycleID = cycles.first(where: \.isActive)?.id ?? cycles.first?.id
    }

    // MARK: - Reset

    func reset() {
        companyName = ""
        role = ""
        location = ""
        jobURL = ""
        jobDescription = ""
        status = .saved
        priority = .medium
        source = .jobPortal
        platform = .other
        interviewStage = nil
        currency = .usd
        salaryMinString = ""
        salaryMaxString = ""
        postedBonusString = ""
        postedEquityString = ""
        expectedSalaryMinString = ""
        expectedSalaryMaxString = ""
        expectedBonusString = ""
        expectedEquityString = ""
        offerBaseString = ""
        offerBonusString = ""
        offerEquityString = ""
        selectedCycleID = nil
        showExpectedCompensation = false
        showOfferCompensation = false
        appliedDate = nil
        hasAppliedDate = false
        nextFollowUpDate = nil
        hasFollowUpDate = false
        isEditing = false
        editingApplication = nil
    }

    private func parseInteger(from string: String) -> Int? {
        Int(
            string
                .replacingOccurrences(of: ",", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func resolvedCycle(context: ModelContext, shouldCreateDefault: Bool) throws -> JobSearchCycle? {
        if let selectedCycleID {
            return try JobSearchCycleMigrationService.cycle(withID: selectedCycleID, in: context)
        }

        guard shouldCreateDefault else { return nil }
        return try JobSearchCycleMigrationService.ensureActiveCycle(in: context)
    }
}
