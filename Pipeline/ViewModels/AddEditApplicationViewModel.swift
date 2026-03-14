import Foundation
import SwiftData
import SwiftUI
import PipelineKit

@Observable
final class AddEditApplicationViewModel {
    struct SaveResult {
        let application: JobApplication
        let rejectionStatusActivityID: UUID?

        var needsRejectionLogPrompt: Bool { rejectionStatusActivityID != nil }
    }

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
    var seniorityOverride: SeniorityBand?
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
    var offerPTOText: String = ""
    var offerPTOScoreString: String = ""
    var offerRemotePolicyText: String = ""
    var offerRemotePolicyScoreString: String = ""
    var offerGrowthScoreString: String = ""
    var offerTeamCultureFitScoreString: String = ""
    var selectedCycleID: UUID?
    var showExpectedCompensation = false
    var showOfferCompensation = false
    var appliedDate: Date?
    var hasAppliedDate: Bool = false
    var nextFollowUpDate: Date?
    var hasFollowUpDate: Bool = false
    var isInApplyQueue: Bool = false
    var postedAt: Date?
    var hasPostedAt: Bool = false
    var applicationDeadline: Date?
    var hasApplicationDeadline: Bool = false

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
        seniorityOverride = app.seniorityOverride
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
        offerPTOText = app.offerPTOText ?? ""
        offerPTOScoreString = app.offerPTOScore.map { String($0) } ?? ""
        offerRemotePolicyText = app.offerRemotePolicyText ?? ""
        offerRemotePolicyScoreString = app.offerRemotePolicyScore.map { String($0) } ?? ""
        offerGrowthScoreString = app.offerGrowthScore.map { String($0) } ?? ""
        offerTeamCultureFitScoreString = app.offerTeamCultureFitScore.map { String($0) } ?? ""
        selectedCycleID = app.cycle?.id
        showExpectedCompensation = app.hasExpectedCompensation
        showOfferCompensation = app.hasOfferCompensation
        appliedDate = app.appliedDate
        hasAppliedDate = app.appliedDate != nil
        nextFollowUpDate = app.nextFollowUpDate
        hasFollowUpDate = app.nextFollowUpDate != nil
        isInApplyQueue = app.isQueuedForApplyLater
        postedAt = app.postedAt
        hasPostedAt = app.postedAt != nil
        applicationDeadline = app.applicationDeadline
        hasApplicationDeadline = app.applicationDeadline != nil
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

    var offerPTOScore: Int? {
        parseScore(from: offerPTOScoreString)
    }

    var offerRemotePolicyScore: Int? {
        parseScore(from: offerRemotePolicyScoreString)
    }

    var offerGrowthScore: Int? {
        parseScore(from: offerGrowthScoreString)
    }

    var offerTeamCultureFitScore: Int? {
        parseScore(from: offerTeamCultureFitScoreString)
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

    @MainActor
    func save(context: ModelContext) throws -> SaveResult {
        guard isValid else { throw SaveError.validationFailed(validationErrors) }

        let savedApplication: JobApplication
        var rejectionStatusActivityID: UUID?
        let saveTimestamp = Date()
        let checklistService = ApplicationChecklistService()
        let desiredFollowUpDate = hasFollowUpDate ? nextFollowUpDate : nil

        do {
            if isEditing, let app = editingApplication {
                let previousStatus = app.status
                let previousFollowUpDate = app.nextFollowUpDate
                let hadExistingFollowUpSteps = !(app.followUpSteps?.isEmpty ?? true)

                try updateApplication(app, context: context)
                _ = try CompanyLinkingService.ensureCompanyLinked(for: app, in: context)

                let transitionResult: StatusTransitionResult
                if previousStatus != status {
                    transitionResult = try ApplicationStatusTransitionService.applyStatus(
                        status,
                        to: app,
                        occurredAt: saveTimestamp,
                        in: context
                    )
                } else {
                    transitionResult = StatusTransitionResult(didChange: false)
                }

                if !transitionResult.didChange {
                    try checklistService.sync(for: app, trigger: .statusChanged, in: context)
                } else if context.hasChanges {
                    try context.save()
                }

                if transitionResult.needsRejectionLogPrompt {
                    rejectionStatusActivityID = transitionResult.statusActivityID
                }

                try syncSmartFollowUps(
                    for: app,
                    previousFollowUpDate: previousFollowUpDate,
                    desiredFollowUpDate: desiredFollowUpDate,
                    hadExistingFollowUpSteps: hadExistingFollowUpSteps,
                    shouldEnsureAppliedCadence: previousStatus != .applied && status == .applied,
                    context: context
                )
                try checklistService.sync(for: app, trigger: .statusChanged, in: context)
                ApplicationTimelineRecorderService.recordFollowUpChange(
                    for: app,
                    from: previousFollowUpDate,
                    to: app.nextFollowUpDate,
                    occurredAt: saveTimestamp,
                    in: context
                )
                savedApplication = app
            } else {
                let app = try createApplication(context: context)
                context.insert(app)
                _ = try CompanyLinkingService.ensureCompanyLinked(for: app, in: context)
                try checklistService.sync(for: app, trigger: .applicationCreated, in: context)
                try syncSmartFollowUps(
                    for: app,
                    previousFollowUpDate: nil,
                    desiredFollowUpDate: desiredFollowUpDate,
                    hadExistingFollowUpSteps: false,
                    shouldEnsureAppliedCadence: status == .applied,
                    context: context
                )
                try checklistService.sync(for: app, trigger: .applicationCreated, in: context)
                ApplicationTimelineRecorderService.seedInitialHistory(
                    for: app,
                    occurredAt: saveTimestamp,
                    in: context
                )
                rejectionStatusActivityID = app.status == .rejected ? app.latestRejectionActivity?.id : nil
                savedApplication = app
            }
        } catch {
            context.rollback()
            throw error
        }

        Task {
            @MainActor in
            await NotificationService.shared.syncReminderState(for: savedApplication)
        }

        return SaveResult(
            application: savedApplication,
            rejectionStatusActivityID: rejectionStatusActivityID
        )
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
            seniorityOverride: seniorityOverride,
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
            offerPTOText: showOfferCompensation ? normalizedOfferText(offerPTOText) : nil,
            offerPTOScore: showOfferCompensation ? offerPTOScore : nil,
            offerRemotePolicyText: showOfferCompensation ? normalizedOfferText(offerRemotePolicyText) : nil,
            offerRemotePolicyScore: showOfferCompensation ? offerRemotePolicyScore : nil,
            offerGrowthScore: showOfferCompensation ? offerGrowthScore : nil,
            offerTeamCultureFitScore: showOfferCompensation ? offerTeamCultureFitScore : nil,
            appliedDate: hasAppliedDate ? appliedDate : nil,
            nextFollowUpDate: hasFollowUpDate ? nextFollowUpDate : nil,
            isInApplyQueue: isInApplyQueue,
            queuedAt: isInApplyQueue ? Date() : nil,
            postedAt: hasPostedAt ? postedAt : nil,
            applicationDeadline: hasApplicationDeadline ? applicationDeadline : nil,
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
        app.priority = priority
        app.source = source
        app.platform = platform
        app.interviewStage = interviewStage
        app.currency = currency
        app.setSeniorityOverride(seniorityOverride)
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
        app.setOfferPTO(
            text: showOfferCompensation ? normalizedOfferText(offerPTOText) : nil,
            score: showOfferCompensation ? offerPTOScore : nil
        )
        app.setOfferRemotePolicy(
            text: showOfferCompensation ? normalizedOfferText(offerRemotePolicyText) : nil,
            score: showOfferCompensation ? offerRemotePolicyScore : nil
        )
        app.setOfferGrowthScore(showOfferCompensation ? offerGrowthScore : nil)
        app.setOfferTeamCultureFitScore(showOfferCompensation ? offerTeamCultureFitScore : nil)
        app.appliedDate = hasAppliedDate ? appliedDate : nil
        app.nextFollowUpDate = hasFollowUpDate ? nextFollowUpDate : nil
        app.setApplyQueue(isInApplyQueue)
        app.setPostedAt(hasPostedAt ? postedAt : nil)
        app.setApplicationDeadline(hasApplicationDeadline ? applicationDeadline : nil)
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
        seniorityOverride = nil
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
        offerPTOText = ""
        offerPTOScoreString = ""
        offerRemotePolicyText = ""
        offerRemotePolicyScoreString = ""
        offerGrowthScoreString = ""
        offerTeamCultureFitScoreString = ""
        selectedCycleID = nil
        showExpectedCompensation = false
        showOfferCompensation = false
        appliedDate = nil
        hasAppliedDate = false
        nextFollowUpDate = nil
        hasFollowUpDate = false
        isInApplyQueue = false
        postedAt = nil
        hasPostedAt = false
        applicationDeadline = nil
        hasApplicationDeadline = false
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

    private func parseScore(from string: String) -> Int? {
        guard let value = parseInteger(from: string) else { return nil }
        return min(max(value, 1), 5)
    }

    private func normalizedOfferText(_ string: String) -> String? {
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private func resolvedCycle(context: ModelContext, shouldCreateDefault: Bool) throws -> JobSearchCycle? {
        if let selectedCycleID {
            return try JobSearchCycleMigrationService.cycle(withID: selectedCycleID, in: context)
        }

        guard shouldCreateDefault else { return nil }
        return try JobSearchCycleMigrationService.ensureActiveCycle(in: context)
    }

    @MainActor
    private func syncSmartFollowUps(
        for application: JobApplication,
        previousFollowUpDate: Date?,
        desiredFollowUpDate: Date?,
        hadExistingFollowUpSteps: Bool,
        shouldEnsureAppliedCadence: Bool,
        context: ModelContext
    ) throws {
        if shouldEnsureAppliedCadence {
            try SmartFollowUpService.shared.ensureAppliedCadence(for: application, in: context)
        } else {
            _ = try SmartFollowUpService.shared.refresh(application, in: context)
            if context.hasChanges {
                try context.save()
            }
        }

        if let desiredFollowUpDate {
            try SmartFollowUpService.shared.applyManualFollowUpDate(
                desiredFollowUpDate,
                for: application,
                in: context
            )
        } else if hadExistingFollowUpSteps && previousFollowUpDate != nil {
            try SmartFollowUpService.shared.applyManualFollowUpDate(
                nil,
                for: application,
                in: context
            )
        }
    }
}
