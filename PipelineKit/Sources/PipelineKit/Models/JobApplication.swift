import Foundation
import SwiftData

@Model
public final class JobApplication {
    public var id: UUID = UUID()
    public var companyName: String = ""
    public var role: String = ""
    public var location: String = ""
    public var jobURL: String?
    public var jobDescription: String?
    public var overviewMarkdown: String?

    public private(set) var statusRawValue: String = ApplicationStatus.saved.rawValue
    public private(set) var priorityRawValue: String = Priority.medium.rawValue
    private var sourceRawValue: String = Source.jobPortal.rawValue
    private var platformRawValue: String = Platform.other.rawValue
    private var interviewStageRawValue: String?
    private var currencyRawValue: String = Currency.usd.rawValue
    private var seniorityOverrideRawValue: String?

    public private(set) var salaryMin: Int?
    public private(set) var salaryMax: Int?
    public private(set) var postedBonusCompensation: Int?
    public private(set) var postedEquityCompensation: Int?
    public private(set) var expectedSalaryMin: Int?
    public private(set) var expectedSalaryMax: Int?
    public private(set) var expectedBonusCompensation: Int?
    public private(set) var expectedEquityCompensation: Int?
    public private(set) var offerBaseCompensation: Int?
    public private(set) var offerBonusCompensation: Int?
    public private(set) var offerEquityCompensation: Int?
    public private(set) var offerPTOText: String?
    public private(set) var offerPTOScore: Int?
    public private(set) var offerRemotePolicyText: String?
    public private(set) var offerRemotePolicyScore: Int?
    public private(set) var offerGrowthScore: Int?
    public private(set) var offerTeamCultureFitScore: Int?
    public var appliedDate: Date?
    public var nextFollowUpDate: Date?
    public var isInApplyQueue: Bool = false
    public var queuedAt: Date?
    public var postedAt: Date?
    public var applicationDeadline: Date?
    public var dismissedChecklistTemplateIDs: [String] = []

    public var cycle: JobSearchCycle?
    public var originCycle: JobSearchCycle?
    public var company: CompanyProfile?

    @Relationship(deleteRule: .cascade, inverse: \InterviewLog.application)
    public var interviewLogs: [InterviewLog]?

    @Relationship(deleteRule: .cascade, inverse: \ApplicationContactLink.application)
    public var contactLinks: [ApplicationContactLink]?

    @Relationship(deleteRule: .cascade, inverse: \ApplicationActivity.application)
    public var activities: [ApplicationActivity]?

    @Relationship(deleteRule: .cascade, inverse: \ApplicationTask.application)
    public var tasks: [ApplicationTask]?

    @Relationship(deleteRule: .cascade, inverse: \FollowUpStep.application)
    public var followUpSteps: [FollowUpStep]?

    @Relationship(deleteRule: .cascade, inverse: \ApplicationChecklistSuggestion.application)
    public var checklistSuggestions: [ApplicationChecklistSuggestion]?

    @Relationship(deleteRule: .cascade, inverse: \ResumeJobSnapshot.application)
    public var resumeSnapshots: [ResumeJobSnapshot]?

    @Relationship(deleteRule: .cascade, inverse: \CoverLetterDraft.application)
    public var coverLetterDraft: CoverLetterDraft?

    @Relationship(deleteRule: .cascade, inverse: \JobMatchAssessment.application)
    public var matchAssessment: JobMatchAssessment?

    @Relationship(deleteRule: .cascade, inverse: \ATSCompatibilityAssessment.application)
    public var atsAssessment: ATSCompatibilityAssessment?

    @Relationship(deleteRule: .cascade, inverse: \ATSCompatibilityScanRun.application)
    public var atsScanRuns: [ATSCompatibilityScanRun]?

    @Relationship(deleteRule: .cascade, inverse: \ApplicationAttachment.application)
    public var attachments: [ApplicationAttachment]?

    @Relationship(deleteRule: .cascade, inverse: \ReferralAttempt.application)
    public var referralAttempts: [ReferralAttempt]?

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    // MARK: - Computed Properties for Enums

    public var status: ApplicationStatus {
        get { ApplicationStatus(rawValue: statusRawValue) }
        set {
            guard statusRawValue != newValue.rawValue else { return }
            statusRawValue = newValue.rawValue
            if newValue != .saved {
                isInApplyQueue = false
                queuedAt = nil
            }
            updateTimestamp()
        }
    }

    public var priority: Priority {
        get { Priority(rawValue: priorityRawValue) ?? .medium }
        set {
            guard priorityRawValue != newValue.rawValue else { return }
            priorityRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var source: Source {
        get { Source(rawValue: sourceRawValue) }
        set {
            guard sourceRawValue != newValue.rawValue else { return }
            sourceRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var platform: Platform {
        get { Platform(rawValue: platformRawValue) ?? .other }
        set {
            guard platformRawValue != newValue.rawValue else { return }
            platformRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var interviewStage: InterviewStage? {
        get {
            guard let rawValue = interviewStageRawValue,
                  !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { return nil }
            return InterviewStage(rawValue: rawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard interviewStageRawValue != newRawValue else { return }
            interviewStageRawValue = newRawValue
            updateTimestamp()
        }
    }

    public var currency: Currency {
        get { Currency(rawValue: currencyRawValue) ?? .usd }
        set {
            guard currencyRawValue != newValue.rawValue else { return }
            currencyRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var seniorityOverride: SeniorityBand? {
        get {
            guard let seniorityOverrideRawValue,
                  !seniorityOverrideRawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return SeniorityBand(rawValue: seniorityOverrideRawValue)
        }
        set {
            let newRawValue = newValue?.rawValue
            guard seniorityOverrideRawValue != newRawValue else { return }
            seniorityOverrideRawValue = newRawValue
            updateTimestamp()
        }
    }

    // MARK: - Computed Properties

    public var salaryRange: String? {
        currency.formatRange(min: salaryMin, max: salaryMax)
    }

    public var expectedSalaryRange: String? {
        currency.formatRange(min: expectedSalaryMin, max: expectedSalaryMax)
    }

    public var postedTotalCompRange: String? {
        currency.formatRange(min: postedTotalCompMin, max: postedTotalCompMax)
    }

    public var expectedTotalCompRange: String? {
        currency.formatRange(min: expectedTotalCompMin, max: expectedTotalCompMax)
    }

    public var offerTotalCompText: String? {
        guard let total = offerTotalComp else { return nil }
        return currency.format(total)
    }

    public var offerYearOneTotalCompText: String? {
        guard let total = offerYearOneTotalComp else { return nil }
        return currency.format(total)
    }

    public var postedTotalCompMin: Int? {
        totalCompensation(base: salaryMin, bonus: postedBonusCompensation, equity: postedEquityCompensation)
    }

    public var postedTotalCompMax: Int? {
        totalCompensation(base: salaryMax, bonus: postedBonusCompensation, equity: postedEquityCompensation)
    }

    public var expectedTotalCompMin: Int? {
        totalCompensation(base: expectedSalaryMin, bonus: expectedBonusCompensation, equity: expectedEquityCompensation)
    }

    public var expectedTotalCompMax: Int? {
        totalCompensation(base: expectedSalaryMax, bonus: expectedBonusCompensation, equity: expectedEquityCompensation)
    }

    public var offerTotalComp: Int? {
        offerYearOneTotalComp
    }

    public var offerEquityYearOneCompensation: Int? {
        offerEquityCompensation.map { $0 / 4 }
    }

    public var offerYearOneTotalComp: Int? {
        totalCompensation(
            base: offerBaseCompensation,
            bonus: offerBonusCompensation,
            equity: offerEquityYearOneCompensation
        )
    }

    public var inferredSeniority: SeniorityBand? {
        SeniorityBand.inferred(from: role)
    }

    public var effectiveSeniority: SeniorityBand? {
        seniorityOverride ?? inferredSeniority
    }

    public var normalizedRoleFamily: String {
        SeniorityBand.normalizedRoleFamily(from: role)
    }

    public var hasExpectedCompensation: Bool {
        expectedSalaryMin != nil ||
        expectedSalaryMax != nil ||
        expectedBonusCompensation != nil ||
        expectedEquityCompensation != nil
    }

    public var hasOfferCompensation: Bool {
        offerBaseCompensation != nil ||
        offerBonusCompensation != nil ||
        offerEquityCompensation != nil
    }

    public var hasOfferDetails: Bool {
        hasOfferCompensation ||
        offerPTOText != nil ||
        offerPTOScore != nil ||
        offerRemotePolicyText != nil ||
        offerRemotePolicyScore != nil ||
        offerGrowthScore != nil ||
        offerTeamCultureFitScore != nil
    }

    public var submittedAt: Date? {
        if let appliedDate {
            return appliedDate
        }

        if status.sortOrder >= ApplicationStatus.applied.sortOrder {
            return updatedAt
        }

        return nil
    }

    public var isQueuedForApplyLater: Bool {
        status == .saved && isInApplyQueue
    }

    public var sortedInterviewLogs: [InterviewLog] {
        (interviewLogs ?? []).sorted { $0.date > $1.date }
    }

    public var sortedContactLinks: [ApplicationContactLink] {
        (contactLinks ?? []).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }

            if lhs.role != rhs.role {
                return lhs.role.displayName.localizedCaseInsensitiveCompare(rhs.role.displayName) == .orderedAscending
            }

            let lhsName = lhs.contact?.fullName ?? ""
            let rhsName = rhs.contact?.fullName ?? ""
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }

    public var sortedActivities: [ApplicationActivity] {
        (activities ?? []).sorted { lhs, rhs in
            if lhs.occurredAt != rhs.occurredAt {
                return lhs.occurredAt > rhs.occurredAt
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    public var sortedInterviewActivities: [ApplicationActivity] {
        sortedActivities.filter { $0.kind == .interview }
    }

    public var pendingInterviewDebriefs: [ApplicationActivity] {
        sortedInterviewActivities.filter(\.needsDebrief)
    }

    public var sortedReferralAttempts: [ReferralAttempt] {
        (referralAttempts ?? []).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    public var hasReceivedReferral: Bool {
        sortedReferralAttempts.contains(where: { $0.status == .received })
    }

    public var sortedRejectionActivities: [ApplicationActivity] {
        sortedActivities.filter(\.isRejectionStatusChange)
    }

    public var latestRejectionActivity: ApplicationActivity? {
        sortedRejectionActivities.first
    }

    public var latestRejectionLog: RejectionLog? {
        latestRejectionActivity?.rejectionLog
    }

    public var needsRejectionLog: Bool {
        latestRejectionActivity?.needsRejectionLog == true
    }

    public var sortedTasks: [ApplicationTask] {
        (tasks ?? []).sorted { lhs, rhs in
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }

            switch (lhs.dueDate, rhs.dueDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }

            if lhs.priority.sortOrder != rhs.priority.sortOrder {
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    public var sortedFollowUpSteps: [FollowUpStep] {
        (followUpSteps ?? []).sorted { lhs, rhs in
            let lhsActive = lhs.isActive
            let rhsActive = rhs.isActive
            if lhsActive != rhsActive {
                return lhsActive && !rhsActive
            }

            if lhsActive && rhsActive {
                if lhs.dueDate != rhs.dueDate {
                    return lhs.dueDate < rhs.dueDate
                }
            } else {
                switch (lhs.state, rhs.state) {
                case (.completed, .dismissed):
                    return true
                case (.dismissed, .completed):
                    return false
                default:
                    let lhsDate = lhs.completedAt ?? lhs.updatedAt
                    let rhsDate = rhs.completedAt ?? rhs.updatedAt
                    if lhsDate != rhsDate {
                        return lhsDate > rhsDate
                    }
                }
            }

            if lhs.cadenceKind != rhs.cadenceKind {
                return lhs.cadenceKind.rawValue.localizedCaseInsensitiveCompare(rhs.cadenceKind.rawValue) == .orderedAscending
            }

            if lhs.sequenceIndex != rhs.sequenceIndex {
                return lhs.sequenceIndex < rhs.sequenceIndex
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    public var activeFollowUpSteps: [FollowUpStep] {
        sortedFollowUpSteps.filter(\.isActive)
    }

    public var nextPendingFollowUpStep: FollowUpStep? {
        activeFollowUpSteps.first
    }

    public var sortedATSScanRuns: [ATSCompatibilityScanRun] {
        (atsScanRuns ?? []).sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    public var sortedChecklistTasks: [ApplicationTask] {
        sortedTasks.filter(\.isSmartChecklistItem)
    }

    public var sortedManualTasks: [ApplicationTask] {
        sortedTasks.filter { !$0.isSmartChecklistItem }
    }

    public var sortedChecklistSuggestions: [ApplicationChecklistSuggestion] {
        (checklistSuggestions ?? []).sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status.sortOrder < rhs.status.sortOrder
            }

            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    public var pendingChecklistSuggestions: [ApplicationChecklistSuggestion] {
        sortedChecklistSuggestions.filter { $0.status == .pending }
    }

    public var primaryContactLink: ApplicationContactLink? {
        sortedContactLinks.first(where: \.isPrimary)
    }

    public var sortedResumeSnapshots: [ResumeJobSnapshot] {
        (resumeSnapshots ?? []).sorted { $0.createdAt > $1.createdAt }
    }

    public var sortedAttachments: [ApplicationAttachment] {
        (attachments ?? []).sorted { lhs, rhs in
            if lhs.category != rhs.category {
                return lhs.category.displayName.localizedCaseInsensitiveCompare(rhs.category.displayName) == .orderedAscending
            }

            if lhs.isSubmittedResume != rhs.isSubmittedResume {
                return lhs.isSubmittedResume && !rhs.isSubmittedResume
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt > rhs.createdAt
            }

            return lhs.resolvedTitle.localizedCaseInsensitiveCompare(rhs.resolvedTitle) == .orderedAscending
        }
    }

    public var submittedResumeAttachment: ApplicationAttachment? {
        sortedAttachments.first(where: \.isSubmittedResume)
    }

    public var companyDomain: String? {
        if let websiteURL = company?.websiteURL,
           let domain = URLHelpers.extractDomain(from: websiteURL) {
            return domain
        }

        let cleaned = companyName.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "inc", with: "")
            .replacingOccurrences(of: "ltd", with: "")
            .replacingOccurrences(of: "llc", with: "")

        return "\(cleaned).com"
    }

    public func googleS2FaviconURL(size: Int = 64) -> URL? {
        let domainFromJobURL = jobURL.flatMap { URLHelpers.extractCompanyDomain(from: $0) }
        let domain = domainFromJobURL ?? companyDomain
        guard let domain else { return nil }
        return URLHelpers.googleFaviconURL(domain: domain, size: size)
    }

    public var companyInitial: String {
        String(companyName.prefix(1)).uppercased()
    }

    // MARK: - Initializer

    public init(
        id: UUID = UUID(),
        companyName: String,
        role: String,
        location: String,
        jobURL: String? = nil,
        jobDescription: String? = nil,
        overviewMarkdown: String? = nil,
        status: ApplicationStatus = .saved,
        priority: Priority = .medium,
        source: Source = .jobPortal,
        platform: Platform = .other,
        interviewStage: InterviewStage? = nil,
        currency: Currency = .usd,
        seniorityOverride: SeniorityBand? = nil,
        salaryMin: Int? = nil,
        salaryMax: Int? = nil,
        postedBonusCompensation: Int? = nil,
        postedEquityCompensation: Int? = nil,
        expectedSalaryMin: Int? = nil,
        expectedSalaryMax: Int? = nil,
        expectedBonusCompensation: Int? = nil,
        expectedEquityCompensation: Int? = nil,
        offerBaseCompensation: Int? = nil,
        offerBonusCompensation: Int? = nil,
        offerEquityCompensation: Int? = nil,
        offerPTOText: String? = nil,
        offerPTOScore: Int? = nil,
        offerRemotePolicyText: String? = nil,
        offerRemotePolicyScore: Int? = nil,
        offerGrowthScore: Int? = nil,
        offerTeamCultureFitScore: Int? = nil,
        appliedDate: Date? = nil,
        nextFollowUpDate: Date? = nil,
        isInApplyQueue: Bool = false,
        queuedAt: Date? = nil,
        postedAt: Date? = nil,
        applicationDeadline: Date? = nil,
        dismissedChecklistTemplateIDs: [String] = [],
        cycle: JobSearchCycle? = nil,
        company: CompanyProfile? = nil,
        interviewLogs: [InterviewLog]? = nil,
        contactLinks: [ApplicationContactLink]? = nil,
        activities: [ApplicationActivity]? = nil,
        tasks: [ApplicationTask]? = nil,
        followUpSteps: [FollowUpStep]? = nil,
        checklistSuggestions: [ApplicationChecklistSuggestion]? = nil,
        resumeSnapshots: [ResumeJobSnapshot]? = nil,
        coverLetterDraft: CoverLetterDraft? = nil,
        matchAssessment: JobMatchAssessment? = nil,
        atsAssessment: ATSCompatibilityAssessment? = nil,
        atsScanRuns: [ATSCompatibilityScanRun]? = nil,
        attachments: [ApplicationAttachment]? = nil,
        referralAttempts: [ReferralAttempt]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.companyName = companyName
        self.role = role
        self.location = location
        self.jobURL = jobURL
        self.jobDescription = jobDescription
        self.overviewMarkdown = overviewMarkdown
        self.statusRawValue = status.rawValue
        self.priorityRawValue = priority.rawValue
        self.sourceRawValue = source.rawValue
        self.platformRawValue = platform.rawValue
        self.interviewStageRawValue = interviewStage?.rawValue
        self.currencyRawValue = currency.rawValue
        self.seniorityOverrideRawValue = seniorityOverride?.rawValue
        self.salaryMin = salaryMin
        self.salaryMax = salaryMax
        self.postedBonusCompensation = postedBonusCompensation
        self.postedEquityCompensation = postedEquityCompensation
        self.expectedSalaryMin = expectedSalaryMin
        self.expectedSalaryMax = expectedSalaryMax
        self.expectedBonusCompensation = expectedBonusCompensation
        self.expectedEquityCompensation = expectedEquityCompensation
        self.offerBaseCompensation = offerBaseCompensation
        self.offerBonusCompensation = offerBonusCompensation
        self.offerEquityCompensation = offerEquityCompensation
        self.offerPTOText = Self.normalizedOfferText(offerPTOText)
        self.offerPTOScore = Self.clampedOfferScore(offerPTOScore)
        self.offerRemotePolicyText = Self.normalizedOfferText(offerRemotePolicyText)
        self.offerRemotePolicyScore = Self.clampedOfferScore(offerRemotePolicyScore)
        self.offerGrowthScore = Self.clampedOfferScore(offerGrowthScore)
        self.offerTeamCultureFitScore = Self.clampedOfferScore(offerTeamCultureFitScore)
        setSalaryRange(min: salaryMin, max: salaryMax, shouldTouch: false)
        setExpectedSalaryRange(min: expectedSalaryMin, max: expectedSalaryMax, shouldTouch: false)
        self.appliedDate = appliedDate
        self.nextFollowUpDate = nextFollowUpDate
        self.isInApplyQueue = isInApplyQueue && status == .saved
        self.queuedAt = isInApplyQueue && status == .saved ? queuedAt : nil
        self.postedAt = postedAt
        self.applicationDeadline = applicationDeadline
        self.dismissedChecklistTemplateIDs = dismissedChecklistTemplateIDs
        self.cycle = cycle
        self.company = company
        self.interviewLogs = interviewLogs
        self.contactLinks = contactLinks
        self.activities = activities
        self.tasks = tasks
        self.followUpSteps = followUpSteps
        self.checklistSuggestions = checklistSuggestions
        self.resumeSnapshots = resumeSnapshots
        self.coverLetterDraft = coverLetterDraft
        self.matchAssessment = matchAssessment
        self.atsAssessment = atsAssessment
        self.atsScanRuns = atsScanRuns
        self.attachments = attachments
        self.referralAttempts = referralAttempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Methods

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public func assignCycle(_ cycle: JobSearchCycle?) {
        guard self.cycle?.id != cycle?.id else { return }
        if originCycle == nil, self.cycle != nil {
            originCycle = self.cycle
        }
        self.cycle = cycle
        updateTimestamp()
        cycle?.updateTimestamp()
    }

    public func assignCompany(_ company: CompanyProfile?) {
        guard self.company?.id != company?.id else { return }
        self.company = company
        updateTimestamp()
        company?.updateTimestamp()
    }

    public func addInterviewLog(_ log: InterviewLog) {
        if interviewLogs == nil {
            interviewLogs = []
        }
        interviewLogs?.append(log)
        updateTimestamp()
    }

    public func addContactLink(_ link: ApplicationContactLink) {
        if contactLinks == nil {
            contactLinks = []
        }
        contactLinks?.append(link)
        updateTimestamp()
    }

    public func addActivity(_ activity: ApplicationActivity) {
        if activities == nil {
            activities = []
        }
        activities?.append(activity)
        updateTimestamp()
    }

    public func addReferralAttempt(_ attempt: ReferralAttempt) {
        if referralAttempts == nil {
            referralAttempts = []
        }
        referralAttempts?.append(attempt)
        updateTimestamp()
    }

    public func addTask(_ task: ApplicationTask) {
        if tasks == nil {
            tasks = []
        }
        tasks?.append(task)
        updateTimestamp()
    }

    public func setApplyQueue(
        _ isQueued: Bool,
        queuedAt date: Date? = nil,
        shouldTouch: Bool = true
    ) {
        let resolvedIsQueued = isQueued && status == .saved
        self.isInApplyQueue = resolvedIsQueued
        queuedAt = resolvedIsQueued ? (date ?? queuedAt ?? Date()) : nil
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setPostedAt(_ date: Date?, shouldTouch: Bool = true) {
        postedAt = date
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setApplicationDeadline(_ date: Date?, shouldTouch: Bool = true) {
        applicationDeadline = date
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func addChecklistSuggestion(_ suggestion: ApplicationChecklistSuggestion) {
        if checklistSuggestions == nil {
            checklistSuggestions = []
        }
        checklistSuggestions?.append(suggestion)
        updateTimestamp()
    }

    public func dismissChecklistTemplate(id: String) {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !dismissedChecklistTemplateIDs.contains(normalized) else { return }
        dismissedChecklistTemplateIDs.append(normalized)
        updateTimestamp()
    }

    public func restoreDismissedChecklistTemplate(id: String) {
        let normalized = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let previousCount = dismissedChecklistTemplateIDs.count
        dismissedChecklistTemplateIDs.removeAll(where: { $0 == normalized })
        if dismissedChecklistTemplateIDs.count != previousCount {
            updateTimestamp()
        }
    }

    public func setSalaryRange(min: Int?, max: Int?, shouldTouch: Bool = true) {
        guard let min, let max else {
            salaryMin = min
            salaryMax = max
            if shouldTouch {
                updateTimestamp()
            }
            return
        }

        if min <= max {
            salaryMin = min
            salaryMax = max
        } else {
            salaryMin = max
            salaryMax = min
        }

        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setSeniorityOverride(_ seniority: SeniorityBand?, shouldTouch: Bool = true) {
        let rawValue = seniority?.rawValue
        guard seniorityOverrideRawValue != rawValue else { return }
        seniorityOverrideRawValue = rawValue
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setPostedAdditionalCompensation(
        bonus: Int?,
        equity: Int?,
        shouldTouch: Bool = true
    ) {
        postedBonusCompensation = bonus
        postedEquityCompensation = equity
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setExpectedSalaryRange(min: Int?, max: Int?, shouldTouch: Bool = true) {
        guard let min, let max else {
            expectedSalaryMin = min
            expectedSalaryMax = max
            if shouldTouch {
                updateTimestamp()
            }
            return
        }

        if min <= max {
            expectedSalaryMin = min
            expectedSalaryMax = max
        } else {
            expectedSalaryMin = max
            expectedSalaryMax = min
        }

        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setExpectedAdditionalCompensation(
        bonus: Int?,
        equity: Int?,
        shouldTouch: Bool = true
    ) {
        expectedBonusCompensation = bonus
        expectedEquityCompensation = equity
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setOfferCompensation(
        base: Int?,
        bonus: Int?,
        equity: Int?,
        shouldTouch: Bool = true
    ) {
        offerBaseCompensation = base
        offerBonusCompensation = bonus
        offerEquityCompensation = equity
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setOfferPTO(
        text: String?,
        score: Int?,
        shouldTouch: Bool = true
    ) {
        offerPTOText = Self.normalizedOfferText(text)
        offerPTOScore = Self.clampedOfferScore(score)
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setOfferRemotePolicy(
        text: String?,
        score: Int?,
        shouldTouch: Bool = true
    ) {
        offerRemotePolicyText = Self.normalizedOfferText(text)
        offerRemotePolicyScore = Self.clampedOfferScore(score)
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setOfferGrowthScore(
        _ score: Int?,
        shouldTouch: Bool = true
    ) {
        offerGrowthScore = Self.clampedOfferScore(score)
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func setOfferTeamCultureFitScore(
        _ score: Int?,
        shouldTouch: Bool = true
    ) {
        offerTeamCultureFitScore = Self.clampedOfferScore(score)
        if shouldTouch {
            updateTimestamp()
        }
    }

    public func addAttachment(_ attachment: ApplicationAttachment) {
        if attachments == nil {
            attachments = []
        }
        attachments?.append(attachment)
        updateTimestamp()
    }

    public func assignCoverLetterDraft(_ draft: CoverLetterDraft?) {
        guard coverLetterDraft?.id != draft?.id else { return }
        coverLetterDraft = draft
        updateTimestamp()
    }

    public func assignMatchAssessment(_ assessment: JobMatchAssessment?) {
        guard matchAssessment?.id != assessment?.id else { return }
        matchAssessment = assessment
        updateTimestamp()
    }

    public func assignATSAssessment(_ assessment: ATSCompatibilityAssessment?) {
        guard atsAssessment?.id != assessment?.id else { return }
        atsAssessment = assessment
        updateTimestamp()
    }

    public func addATSScanRun(_ run: ATSCompatibilityScanRun) {
        if atsScanRuns == nil {
            atsScanRuns = []
        }
        atsScanRuns?.append(run)
    }

    private func totalCompensation(base: Int?, bonus: Int?, equity: Int?) -> Int? {
        guard base != nil || bonus != nil || equity != nil else { return nil }
        return (base ?? 0) + (bonus ?? 0) + (equity ?? 0)
    }

    private static func normalizedOfferText(_ text: String?) -> String? {
        guard let text else { return nil }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func clampedOfferScore(_ score: Int?) -> Int? {
        guard let score else { return nil }
        return min(max(score, 1), 5)
    }

    public func addFollowUpStep(_ step: FollowUpStep) {
        if followUpSteps == nil {
            followUpSteps = []
        }
        if followUpSteps?.contains(where: { $0.id == step.id }) != true {
            followUpSteps?.append(step)
        }
        step.application = self
        updateTimestamp()
    }
}
