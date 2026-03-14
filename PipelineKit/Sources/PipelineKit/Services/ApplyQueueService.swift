import Foundation

public struct ApplyQueueItem: Identifiable {
    public let application: JobApplication
    public let preparationStatus: SavedApplicationPreparationStatus
    public let freshMatchScore: Int?
    public let isMatchScoreStale: Bool
    public let estimatedMinutes: Int

    public init(
        application: JobApplication,
        preparationStatus: SavedApplicationPreparationStatus,
        freshMatchScore: Int?,
        isMatchScoreStale: Bool,
        estimatedMinutes: Int
    ) {
        self.application = application
        self.preparationStatus = preparationStatus
        self.freshMatchScore = freshMatchScore
        self.isMatchScoreStale = isMatchScoreStale
        self.estimatedMinutes = estimatedMinutes
    }

    public var id: UUID {
        application.id
    }

    public var applicationDeadline: Date? {
        application.applicationDeadline
    }

    public var postedAt: Date? {
        application.postedAt
    }

    public var queuedAt: Date? {
        application.queuedAt
    }
}

public struct ApplyQueueSnapshot {
    public let todayQueue: [ApplyQueueItem]
    public let backlog: [ApplyQueueItem]
    public let totalEstimatedMinutes: Int

    public init(
        todayQueue: [ApplyQueueItem],
        backlog: [ApplyQueueItem],
        totalEstimatedMinutes: Int
    ) {
        self.todayQueue = todayQueue
        self.backlog = backlog
        self.totalEstimatedMinutes = totalEstimatedMinutes
    }

    public var queuedCount: Int {
        todayQueue.count + backlog.count
    }
}

public struct ApplyQueueService {
    public static let defaultDailyTarget = 4
    public static let recommendedRange = 3...5
    public static let baseApplyMinutes = 30
    public static let resumePreparationMinutes = 30
    public static let coverLetterPreparationMinutes = 20
    public static let companyResearchPreparationMinutes = 10

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func snapshot(
        from applications: [JobApplication],
        dailyTarget: Int,
        currentResumeRevisionID: UUID?,
        matchPreferences: JobMatchPreferences
    ) -> ApplyQueueSnapshot {
        let eligibleItems = applications
            .filter { $0.status == .saved && $0.isInApplyQueue }
            .map {
                makeItem(
                    for: $0,
                    currentResumeRevisionID: currentResumeRevisionID,
                    matchPreferences: matchPreferences
                )
            }
            .sorted(by: compareQueueItems)

        let clampedTarget = max(1, dailyTarget)
        let todayQueue = Array(eligibleItems.prefix(clampedTarget))
        let backlog = Array(eligibleItems.dropFirst(clampedTarget))

        return ApplyQueueSnapshot(
            todayQueue: todayQueue,
            backlog: backlog,
            totalEstimatedMinutes: todayQueue.reduce(0) { $0 + $1.estimatedMinutes }
        )
    }

    public func nextNotificationDate(
        hour: Int,
        minute: Int,
        referenceDate: Date = Date()
    ) -> Date? {
        let safeHour = min(max(hour, 0), 23)
        let safeMinute = min(max(minute, 0), 59)
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = safeHour
        components.minute = safeMinute

        let todayCandidate = calendar.date(from: components)
        if let todayCandidate, todayCandidate > referenceDate {
            return todayCandidate
        }

        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) else {
            return todayCandidate
        }
        var tomorrowComponents = calendar.dateComponents([.year, .month, .day], from: tomorrow)
        tomorrowComponents.hour = safeHour
        tomorrowComponents.minute = safeMinute
        return calendar.date(from: tomorrowComponents)
    }

    private func makeItem(
        for application: JobApplication,
        currentResumeRevisionID: UUID?,
        matchPreferences: JobMatchPreferences
    ) -> ApplyQueueItem {
        let prepStatus = SavedApplicationPreparationService.status(for: application)
        let stale = application.matchAssessment.map {
            JobMatchScoringService.isStale(
                $0,
                application: application,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: matchPreferences
            )
        } ?? false
        let freshMatchScore: Int?
        if let assessment = application.matchAssessment,
           assessment.status == .ready,
           !stale {
            freshMatchScore = assessment.overallScore
        } else {
            freshMatchScore = nil
        }

        return ApplyQueueItem(
            application: application,
            preparationStatus: prepStatus,
            freshMatchScore: freshMatchScore,
            isMatchScoreStale: stale,
            estimatedMinutes: estimateMinutes(for: prepStatus)
        )
    }

    private func estimateMinutes(for preparationStatus: SavedApplicationPreparationStatus) -> Int {
        var total = Self.baseApplyMinutes
        if !preparationStatus.hasTailoredResume {
            total += Self.resumePreparationMinutes
        }
        if !preparationStatus.hasCoverLetter {
            total += Self.coverLetterPreparationMinutes
        }
        if !preparationStatus.hasCompanyResearch {
            total += Self.companyResearchPreparationMinutes
        }
        return total
    }

    private func compareQueueItems(lhs: ApplyQueueItem, rhs: ApplyQueueItem) -> Bool {
        let lhsScore = lhs.freshMatchScore
        let rhsScore = rhs.freshMatchScore

        switch (lhsScore, rhsScore) {
        case let (lhsScore?, rhsScore?) where lhsScore != rhsScore:
            return lhsScore > rhsScore
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        let lhsDeadline = lhs.application.applicationDeadline ?? .distantFuture
        let rhsDeadline = rhs.application.applicationDeadline ?? .distantFuture
        if lhsDeadline != rhsDeadline {
            return lhsDeadline < rhsDeadline
        }

        let lhsPostedAt = lhs.application.postedAt ?? .distantFuture
        let rhsPostedAt = rhs.application.postedAt ?? .distantFuture
        if lhsPostedAt != rhsPostedAt {
            return lhsPostedAt < rhsPostedAt
        }

        let lhsQueuedAt = lhs.application.queuedAt ?? .distantFuture
        let rhsQueuedAt = rhs.application.queuedAt ?? .distantFuture
        if lhsQueuedAt != rhsQueuedAt {
            return lhsQueuedAt < rhsQueuedAt
        }

        if lhs.application.createdAt != rhs.application.createdAt {
            return lhs.application.createdAt < rhs.application.createdAt
        }

        return lhs.application.id.uuidString < rhs.application.id.uuidString
    }
}
