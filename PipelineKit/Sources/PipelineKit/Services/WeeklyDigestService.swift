import Foundation
import SwiftData

public struct WeeklyDigestSchedule: Hashable, Sendable {
    public let weekday: Int
    public let hour: Int
    public let minute: Int

    public init(weekday: Int, hour: Int, minute: Int) {
        self.weekday = min(max(weekday, 1), 7)
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    public static let sundayEvening = WeeklyDigestSchedule(weekday: 1, hour: 19, minute: 0)
}

public enum WeeklyDigestGenerationResult {
    case created(WeeklyDigestSnapshot)
    case existing(WeeklyDigestSnapshot)
    case noneDue(nextRun: Date)
    case noData(nextRun: Date)
}

public final class WeeklyDigestService: @unchecked Sendable {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    public func nextScheduledRun(
        after referenceDate: Date,
        schedule: WeeklyDigestSchedule
    ) -> Date {
        let currentWeekRun = scheduledRun(containing: referenceDate, schedule: schedule)
        if currentWeekRun > referenceDate {
            return currentWeekRun
        }

        let nextWeekReference = calendar.date(byAdding: .day, value: 7, to: referenceDate) ?? referenceDate
        return scheduledRun(containing: nextWeekReference, schedule: schedule)
    }

    public func latestCompletedInterval(
        asOf referenceDate: Date,
        schedule: WeeklyDigestSchedule
    ) -> DateInterval {
        let latestRun = latestScheduledRun(onOrBefore: referenceDate, schedule: schedule)
        let start = calendar.date(byAdding: .day, value: -7, to: latestRun) ?? latestRun
        return DateInterval(start: start, end: latestRun)
    }

    @discardableResult
    public func generateLatestDigestIfNeeded(
        applications: [JobApplication],
        existingDigests: [WeeklyDigestSnapshot],
        in context: ModelContext,
        currentResumeRevisionID: UUID?,
        matchPreferences: JobMatchPreferences,
        schedule: WeeklyDigestSchedule,
        referenceDate: Date = Date()
    ) throws -> WeeklyDigestGenerationResult {
        let nextRun = nextScheduledRun(after: referenceDate, schedule: schedule)
        let completedInterval = latestCompletedInterval(asOf: referenceDate, schedule: schedule)

        if let existing = existingDigests.first(where: { sameDigestWeek($0.weekStart, completedInterval.start) }) {
            return .existing(existing)
        }

        let liveApplications = applications.filter { $0.status != .archived }
        guard !liveApplications.isEmpty else {
            return .noData(nextRun: nextRun)
        }

        let snapshot = buildSnapshot(
            applications: liveApplications,
            currentResumeRevisionID: currentResumeRevisionID,
            matchPreferences: matchPreferences,
            completedInterval: completedInterval,
            referenceDate: referenceDate
        )

        context.insert(snapshot)
        for insight in snapshot.sortedInsights {
            context.insert(insight)
        }
        for action in snapshot.sortedActionItems {
            context.insert(action)
        }
        try context.save()
        return .created(snapshot)
    }

    private func buildSnapshot(
        applications: [JobApplication],
        currentResumeRevisionID: UUID?,
        matchPreferences: JobMatchPreferences,
        completedInterval: DateInterval,
        referenceDate: Date
    ) -> WeeklyDigestSnapshot {
        let previousInterval = DateInterval(
            start: calendar.date(byAdding: .day, value: -7, to: completedInterval.start) ?? completedInterval.start,
            end: completedInterval.start
        )
        let upcomingInterval = DateInterval(
            start: completedInterval.end,
            end: calendar.date(byAdding: .day, value: 7, to: completedInterval.end) ?? completedInterval.end
        )

        let currentSubmitted = submittedApplications(in: completedInterval, from: applications)
        let previousSubmitted = submittedApplications(in: previousInterval, from: applications)
        let currentResponseRate = responseRate(for: currentSubmitted)
        let previousResponseRate = responseRate(for: previousSubmitted)
        let currentMatchScore = averageFreshMatchScore(
            for: currentSubmitted,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )
        let previousMatchScore = averageFreshMatchScore(
            for: previousSubmitted,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )
        let needsTailoringApps = currentSubmitted.filter {
            applicationNeedsTailoring(
                $0,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: matchPreferences
            )
        }

        let completedInterviews = applications.flatMap(\.sortedInterviewActivities).filter { activity in
            activity.occurredAt >= completedInterval.start &&
            activity.occurredAt < completedInterval.end &&
            !activity.isScheduledInterview
        }

        let upcomingInterviews = applications.flatMap(\.sortedInterviewActivities).filter { activity in
            activity.occurredAt >= upcomingInterval.start &&
            activity.occurredAt < upcomingInterval.end
        }

        let upcomingFollowUps = applications.filter { application in
            guard let followUpDate = application.nextFollowUpDate else { return false }
            return followUpDate >= upcomingInterval.start && followUpDate < upcomingInterval.end
        }

        let startOfToday = calendar.startOfDay(for: referenceDate)
        let overdueFollowUps = applications.filter { application in
            guard let followUpDate = application.nextFollowUpDate else { return false }
            return followUpDate < startOfToday
        }

        let insightCandidates = makeInsightCandidates(
            applications: applications,
            currentSubmitted: currentSubmitted,
            overdueFollowUps: overdueFollowUps,
            referenceDate: referenceDate,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )

        let selectedInsights = Array(insightCandidates.prefix(3))
        let actionItems = makeActionItems(
            applications: applications,
            upcomingInterval: upcomingInterval,
            overdueFollowUps: overdueFollowUps,
            needsTailoringApplications: needsTailoringApps,
            referenceDate: referenceDate
        )

        let snapshot = WeeklyDigestSnapshot(
            weekStart: completedInterval.start,
            weekEnd: completedInterval.end,
            newApplicationsCount: currentSubmitted.count,
            newApplicationsDelta: currentSubmitted.count - previousSubmitted.count,
            responseRate: currentResponseRate,
            previousResponseRate: previousResponseRate,
            interviewsCompletedCount: completedInterviews.count,
            interviewsScheduledCount: upcomingInterviews.count,
            followUpsDueCount: upcomingFollowUps.count,
            overdueFollowUpsCount: overdueFollowUps.count,
            averageMatchScore: currentMatchScore,
            previousAverageMatchScore: previousMatchScore,
            needsTailoringCount: needsTailoringApps.count
        )

        snapshot.insights = selectedInsights.enumerated().map { index, candidate in
            let insight = WeeklyDigestInsight(
                sourceKind: candidate.sourceKind,
                sortOrder: index,
                title: candidate.title,
                body: candidate.body,
                evidenceText: candidate.evidence
            )
            insight.snapshot = snapshot
            return insight
        }

        snapshot.actionItems = actionItems.enumerated().map { index, candidate in
            let action = WeeklyDigestActionItem(
                kind: candidate.kind,
                sortOrder: index,
                title: candidate.title,
                subtitle: candidate.subtitle,
                dueDate: candidate.dueDate,
                applicationID: candidate.applicationID,
                isOverdue: candidate.isOverdue
            )
            action.snapshot = snapshot
            return action
        }

        return snapshot
    }

    private func submittedApplications(
        in interval: DateInterval,
        from applications: [JobApplication]
    ) -> [JobApplication] {
        applications.filter { application in
            guard let submittedAt = application.submittedAt else { return false }
            return submittedAt >= interval.start && submittedAt < interval.end
        }
    }

    private func responseRate(for applications: [JobApplication]) -> Double {
        let nonSaved = applications.filter { $0.status != .saved && $0.status != .archived }
        guard !nonSaved.isEmpty else { return 0 }

        let responded = nonSaved.filter {
            $0.status == .interviewing || $0.status == .offered || $0.status == .rejected
        }.count
        return Double(responded) / Double(nonSaved.count)
    }

    private func interviewConversionRate(for applications: [JobApplication]) -> Double {
        guard !applications.isEmpty else { return 0 }
        let converted = applications.filter { $0.status == .interviewing || $0.status == .offered }.count
        return Double(converted) / Double(applications.count)
    }

    private func averageFreshMatchScore(
        for applications: [JobApplication],
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Double? {
        let scores = applications.compactMap { application -> Int? in
            guard let assessment = application.matchAssessment,
                  assessment.status == .ready,
                  !JobMatchScoringService.isStale(
                    assessment,
                    application: application,
                    currentResumeRevisionID: currentResumeRevisionID,
                    preferences: preferences
                  )
            else {
                return nil
            }

            return assessment.overallScore
        }

        guard !scores.isEmpty else { return nil }
        return Double(scores.reduce(0, +)) / Double(scores.count)
    }

    private func applicationNeedsTailoring(
        _ application: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Bool {
        let hasOpenTailorTask = application.sortedChecklistTasks.contains {
            !$0.isCompleted && $0.checklistTemplateID == "tailorResume"
        }

        guard let assessment = application.matchAssessment else {
            return true
        }

        let stale = JobMatchScoringService.isStale(
            assessment,
            application: application,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: preferences
        )

        return hasOpenTailorTask || assessment.status != .ready || stale
    }

    private struct InsightCandidate {
        let priority: Int
        let sourceKind: WeeklyDigestInsightSourceKind
        let title: String
        let body: String
        let evidence: String?
    }

    private func makeInsightCandidates(
        applications: [JobApplication],
        currentSubmitted: [JobApplication],
        overdueFollowUps: [JobApplication],
        referenceDate: Date,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> [InsightCandidate] {
        var candidates: [InsightCandidate] = []

        if let candidate = followUpHygieneInsight(
            applications: applications,
            overdueFollowUps: overdueFollowUps,
            referenceDate: referenceDate
        ) {
            candidates.append(candidate)
        }
        if let candidate = matchScoreSelectivityInsight(
            applications: applications,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: preferences
        ) {
            candidates.append(candidate)
        }
        if let candidate = sourcePerformanceInsight(applications: applications) {
            candidates.append(candidate)
        }
        if let candidate = weekdayPerformanceInsight(applications: applications) {
            candidates.append(candidate)
        }
        if let candidate = appliedStageStalenessInsight(applications: applications, referenceDate: referenceDate) {
            candidates.append(candidate)
        }

        if candidates.isEmpty {
            let body: String
            if currentSubmitted.isEmpty {
                body = "You did not submit new applications this week, so next week is a good time to restart momentum with a few high-fit roles."
            } else {
                body = "You added \(currentSubmitted.count) application\(currentSubmitted.count == 1 ? "" : "s") this week. Keep the pipeline moving with timely follow-ups and fresh tailoring."
            }
            candidates.append(
                InsightCandidate(
                    priority: 0,
                    sourceKind: .rule,
                    title: "Keep the pipeline moving.",
                    body: body,
                    evidence: nil
                )
            )
        }

        return candidates.sorted { lhs, rhs in
            if lhs.priority != rhs.priority {
                return lhs.priority > rhs.priority
            }
            return lhs.title < rhs.title
        }
    }

    private func followUpHygieneInsight(
        applications: [JobApplication],
        overdueFollowUps: [JobApplication],
        referenceDate: Date
    ) -> InsightCandidate? {
        let overdueTasks = applications.flatMap(\.sortedTasks).filter { task in
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return dueDate < calendar.startOfDay(for: referenceDate)
        }

        let overdueCount = overdueFollowUps.count + overdueTasks.count
        guard overdueCount >= 2 else { return nil }

        return InsightCandidate(
            priority: 100,
            sourceKind: .rule,
            title: "Follow-up hygiene is slipping.",
            body: "You have \(overdueCount) overdue follow-up item\(overdueCount == 1 ? "" : "s"). Clearing the oldest outreach first is the fastest way to unblock responses.",
            evidence: "\(overdueFollowUps.count) overdue follow-up date\(overdueFollowUps.count == 1 ? "" : "s") and \(overdueTasks.count) overdue task\(overdueTasks.count == 1 ? "" : "s")."
        )
    }

    private func matchScoreSelectivityInsight(
        applications: [JobApplication],
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> InsightCandidate? {
        let submitted = applications.filter { $0.submittedAt != nil }
        let highFit = submitted.filter { application in
            guard let assessment = application.matchAssessment,
                  assessment.status == .ready,
                  !JobMatchScoringService.isStale(
                    assessment,
                    application: application,
                    currentResumeRevisionID: currentResumeRevisionID,
                    preferences: preferences
                  ),
                  let score = assessment.overallScore else {
                return false
            }
            return score >= 80
        }

        let lowerFit = submitted.filter { application in
            guard let assessment = application.matchAssessment,
                  assessment.status == .ready,
                  !JobMatchScoringService.isStale(
                    assessment,
                    application: application,
                    currentResumeRevisionID: currentResumeRevisionID,
                    preferences: preferences
                  ),
                  let score = assessment.overallScore else {
                return false
            }
            return score < 80
        }

        guard highFit.count >= 3, lowerFit.count >= 3 else { return nil }

        let highRate = interviewConversionRate(for: highFit)
        let lowRate = interviewConversionRate(for: lowerFit)
        let delta = highRate - lowRate
        guard delta >= 0.15 else { return nil }

        return InsightCandidate(
            priority: 90,
            sourceKind: .rule,
            title: "High-match roles are converting better.",
            body: "Your interview conversion is stronger on roles with 80%+ match scores. Being a bit more selective should improve signal quality.",
            evidence: "80%+ match roles converted at \(percent(highRate)) vs \(percent(lowRate)) for lower-match roles."
        )
    }

    private func sourcePerformanceInsight(applications: [JobApplication]) -> InsightCandidate? {
        let submitted = applications.filter { $0.submittedAt != nil }
        guard submitted.count >= 6 else { return nil }

        let sourceGroups = Dictionary(grouping: submitted, by: \.source.displayName)
            .filter { $0.value.count >= 3 }
        let platformGroups = Dictionary(grouping: submitted, by: \.platform.displayName)
            .filter { $0.value.count >= 3 }

        let bestSource = sourceGroups.max { responseRate(for: $0.value) < responseRate(for: $1.value) }
        let worstSource = sourceGroups.min { responseRate(for: $0.value) < responseRate(for: $1.value) }
        let bestPlatform = platformGroups.max { responseRate(for: $0.value) < responseRate(for: $1.value) }
        let worstPlatform = platformGroups.min { responseRate(for: $0.value) < responseRate(for: $1.value) }

        let sourceCandidate = candidateForPerformancePair(
            best: bestSource,
            worst: worstSource,
            titlePrefix: "Some application sources are outperforming others.",
            bodyTemplate: { bestName, worstName in
                "\(bestName) is producing better response rates than \(worstName). Consider leaning harder into the stronger channel next week."
            }
        )

        let platformCandidate = candidateForPerformancePair(
            best: bestPlatform,
            worst: worstPlatform,
            titlePrefix: "One platform is standing out.",
            bodyTemplate: { bestName, worstName in
                "Applications from \(bestName) are converting better than \(worstName). It may be worth prioritizing that platform for similar roles."
            }
        )

        return [sourceCandidate, platformCandidate]
            .compactMap { $0 }
            .sorted { lhs, rhs in lhs.priority > rhs.priority }
            .first
    }

    private func candidateForPerformancePair(
        best: Dictionary<String, [JobApplication]>.Element?,
        worst: Dictionary<String, [JobApplication]>.Element?,
        titlePrefix: String,
        bodyTemplate: (String, String) -> String
    ) -> InsightCandidate? {
        guard let best, let worst, best.key != worst.key else { return nil }
        let bestRate = responseRate(for: best.value)
        let worstRate = responseRate(for: worst.value)
        let delta = bestRate - worstRate
        guard delta >= 0.15 else { return nil }

        return InsightCandidate(
            priority: Int((delta * 100).rounded()) + 70,
            sourceKind: .rule,
            title: titlePrefix,
            body: bodyTemplate(best.key, worst.key),
            evidence: "\(best.key): \(percent(bestRate)) across \(best.value.count) applications. \(worst.key): \(percent(worstRate)) across \(worst.value.count)."
        )
    }

    private func weekdayPerformanceInsight(applications: [JobApplication]) -> InsightCandidate? {
        let submitted = applications.compactMap { application -> (Int, JobApplication)? in
            guard let submittedAt = application.submittedAt else { return nil }
            return (calendar.component(.weekday, from: submittedAt), application)
        }

        let grouped = Dictionary(grouping: submitted, by: { $0.0 })
            .mapValues { $0.map(\.1) }
            .filter { $0.value.count >= 3 }

        guard let best = grouped.max(by: { responseRate(for: $0.value) < responseRate(for: $1.value) }),
              let worst = grouped.min(by: { responseRate(for: $0.value) < responseRate(for: $1.value) }),
              best.key != worst.key else {
            return nil
        }

        let bestRate = responseRate(for: best.value)
        let worstRate = responseRate(for: worst.value)
        let delta = bestRate - worstRate
        guard delta >= 0.15 else { return nil }

        return InsightCandidate(
            priority: 65,
            sourceKind: .rule,
            title: "Submission timing may be affecting results.",
            body: "Your response rate is stronger on \(weekdayName(best.key)) submissions than on \(weekdayName(worst.key)). Adjusting application timing could help.",
            evidence: "\(weekdayName(best.key)): \(percent(bestRate)) across \(best.value.count) submissions. \(weekdayName(worst.key)): \(percent(worstRate)) across \(worst.value.count)."
        )
    }

    private func appliedStageStalenessInsight(
        applications: [JobApplication],
        referenceDate: Date
    ) -> InsightCandidate? {
        let appliedApps = applications.filter { $0.status == .applied }
        guard appliedApps.count >= 3 else { return nil }

        let totalAge = appliedApps.reduce(0.0) { partial, application in
            let start = application.appliedDate ?? application.createdAt
            return partial + max(0, referenceDate.timeIntervalSince(start) / 86_400)
        }
        let averageAge = totalAge / Double(appliedApps.count)
        guard averageAge > 14 else { return nil }

        return InsightCandidate(
            priority: 60,
            sourceKind: .rule,
            title: "Applied-stage applications are aging out.",
            body: "Several active applications have been sitting in Applied for more than two weeks. Prioritize follow-ups or shift effort into fresher leads.",
            evidence: "\(appliedApps.count) applications are still in Applied with an average age of \(Int(averageAge.rounded())) days."
        )
    }

    private struct ActionCandidate {
        let kind: WeeklyDigestActionKind
        let title: String
        let subtitle: String?
        let dueDate: Date?
        let applicationID: UUID?
        let isOverdue: Bool
        let sortKey: Int
    }

    private func makeActionItems(
        applications: [JobApplication],
        upcomingInterval: DateInterval,
        overdueFollowUps: [JobApplication],
        needsTailoringApplications: [JobApplication],
        referenceDate: Date
    ) -> [ActionCandidate] {
        var items: [ActionCandidate] = []

        let upcomingInterviews = applications.flatMap(\.sortedInterviewActivities)
            .filter { $0.occurredAt >= upcomingInterval.start && $0.occurredAt < upcomingInterval.end }
            .sorted { $0.occurredAt < $1.occurredAt }

        for activity in upcomingInterviews.prefix(3) {
            guard let application = activity.application else { continue }
            items.append(
                ActionCandidate(
                    kind: .interview,
                    title: "Interview at \(application.companyName)",
                    subtitle: application.role,
                    dueDate: activity.occurredAt,
                    applicationID: application.id,
                    isOverdue: false,
                    sortKey: 0
                )
            )
        }

        let sortedOverdueFollowUps = overdueFollowUps.sorted {
            ($0.nextFollowUpDate ?? .distantFuture) < ($1.nextFollowUpDate ?? .distantFuture)
        }
        for application in sortedOverdueFollowUps.prefix(3) {
            items.append(
                ActionCandidate(
                    kind: .followUp,
                    title: "Follow up with \(application.companyName)",
                    subtitle: "Overdue \(overdueDayText(for: application.nextFollowUpDate, referenceDate: referenceDate))",
                    dueDate: application.nextFollowUpDate,
                    applicationID: application.id,
                    isOverdue: true,
                    sortKey: 1
                )
            )
        }

        let upcomingFollowUps = applications
            .filter { application in
                guard let followUpDate = application.nextFollowUpDate else { return false }
                return followUpDate >= upcomingInterval.start && followUpDate < upcomingInterval.end
            }
            .sorted { ($0.nextFollowUpDate ?? .distantFuture) < ($1.nextFollowUpDate ?? .distantFuture) }

        for application in upcomingFollowUps.prefix(2) {
            items.append(
                ActionCandidate(
                    kind: .followUp,
                    title: "Follow up with \(application.companyName)",
                    subtitle: application.role,
                    dueDate: application.nextFollowUpDate,
                    applicationID: application.id,
                    isOverdue: false,
                    sortKey: 2
                )
            )
        }

        for application in needsTailoringApplications.prefix(3) {
            items.append(
                ActionCandidate(
                    kind: .tailoring,
                    title: "Tailor resume for \(application.companyName)",
                    subtitle: application.role,
                    dueDate: nil,
                    applicationID: application.id,
                    isOverdue: false,
                    sortKey: 3
                )
            )
        }

        return items
            .sorted { lhs, rhs in
                if lhs.sortKey != rhs.sortKey {
                    return lhs.sortKey < rhs.sortKey
                }
                switch (lhs.dueDate, rhs.dueDate) {
                case let (lhsDate?, rhsDate?):
                    return lhsDate < rhsDate
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.title < rhs.title
                }
            }
            .prefix(6)
            .map { $0 }
    }

    private func scheduledRun(
        containing referenceDate: Date,
        schedule: WeeklyDigestSchedule
    ) -> Date {
        var components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: referenceDate)
        components.weekday = schedule.weekday
        components.hour = schedule.hour
        components.minute = schedule.minute
        components.second = 0
        return calendar.date(from: components) ?? referenceDate
    }

    private func latestScheduledRun(
        onOrBefore referenceDate: Date,
        schedule: WeeklyDigestSchedule
    ) -> Date {
        let currentWeekRun = scheduledRun(containing: referenceDate, schedule: schedule)
        if referenceDate >= currentWeekRun {
            return currentWeekRun
        }
        return calendar.date(byAdding: .day, value: -7, to: currentWeekRun) ?? currentWeekRun
    }

    private func sameDigestWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }

    private func weekdayName(_ weekday: Int) -> String {
        let index = min(max(weekday - 1, 0), calendar.weekdaySymbols.count - 1)
        return calendar.weekdaySymbols[index]
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func overdueDayText(for date: Date?, referenceDate: Date) -> String {
        guard let date else { return "recently" }
        let dayDelta = max(
            1,
            calendar.dateComponents(
                [.day],
                from: calendar.startOfDay(for: date),
                to: calendar.startOfDay(for: referenceDate)
            ).day ?? 1
        )
        return "by \(dayDelta) day\(dayDelta == 1 ? "" : "s")"
    }
}
