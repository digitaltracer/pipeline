import Foundation

public struct DashboardSnapshot: Sendable {
    public let totalApplications: Int
    public let activeApplications: Int
    public let submittedApplications: Int
    public let interviewingApplications: Int
    public let offeredApplications: Int
    public let responseRate: Double

    public init(
        totalApplications: Int,
        activeApplications: Int,
        submittedApplications: Int,
        interviewingApplications: Int,
        offeredApplications: Int,
        responseRate: Double
    ) {
        self.totalApplications = totalApplications
        self.activeApplications = activeApplications
        self.submittedApplications = submittedApplications
        self.interviewingApplications = interviewingApplications
        self.offeredApplications = offeredApplications
        self.responseRate = responseRate
    }
}

public struct DashboardStatusCount: Identifiable, Sendable {
    public let status: ApplicationStatus
    public let count: Int
    public var id: String { status.rawValue }

    public init(status: ApplicationStatus, count: Int) {
        self.status = status
        self.count = count
    }
}

public struct DashboardTimeInStage: Identifiable, Sendable {
    public let status: ApplicationStatus
    public let averageDays: Double
    public var id: String { status.rawValue }

    public init(status: ApplicationStatus, averageDays: Double) {
        self.status = status
        self.averageDays = averageDays
    }
}

public struct DashboardHeatmapCell: Identifiable, Sendable {
    public let weekStart: Date
    public let weekdayIndex: Int
    public let count: Int
    public var id: String { "\(weekStart.timeIntervalSince1970)-\(weekdayIndex)" }

    public init(weekStart: Date, weekdayIndex: Int, count: Int) {
        self.weekStart = weekStart
        self.weekdayIndex = weekdayIndex
        self.count = count
    }
}

public struct DashboardSalaryBin: Identifiable, Sendable {
    public let label: String
    public let lowerBound: Double
    public let upperBound: Double
    public let count: Int
    public var id: String { label }

    public init(label: String, lowerBound: Double, upperBound: Double, count: Int) {
        self.label = label
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.count = count
    }
}

public struct DashboardGoalProgress: Identifiable, Sendable {
    public let goalID: UUID
    public let title: String
    public let metric: SearchGoalMetric
    public let cadence: SearchGoalCadence
    public let progress: Int
    public let target: Int
    public let periodLabel: String
    public var id: UUID { goalID }

    public init(
        goalID: UUID,
        title: String,
        metric: SearchGoalMetric,
        cadence: SearchGoalCadence,
        progress: Int,
        target: Int,
        periodLabel: String
    ) {
        self.goalID = goalID
        self.title = title
        self.metric = metric
        self.cadence = cadence
        self.progress = progress
        self.target = target
        self.periodLabel = periodLabel
    }
}

public struct DashboardChecklistSnapshot: Sendable {
    public let totalItems: Int
    public let completedItems: Int
    public let openItems: Int
    public let overdueItems: Int
    public let completionRate: Double

    public init(
        totalItems: Int,
        completedItems: Int,
        openItems: Int,
        overdueItems: Int,
        completionRate: Double
    ) {
        self.totalItems = totalItems
        self.completedItems = completedItems
        self.openItems = openItems
        self.overdueItems = overdueItems
        self.completionRate = completionRate
    }
}

public struct DashboardRejectionSummary: Sendable {
    public let rejectedApplications: Int
    public let loggedRejections: Int
    public let missingLogCount: Int
    public let topSignal: String?
    public let topRecoverySuggestion: String?
    public let hasFreshInsights: Bool

    public init(
        rejectedApplications: Int,
        loggedRejections: Int,
        missingLogCount: Int,
        topSignal: String?,
        topRecoverySuggestion: String?,
        hasFreshInsights: Bool
    ) {
        self.rejectedApplications = rejectedApplications
        self.loggedRejections = loggedRejections
        self.missingLogCount = missingLogCount
        self.topSignal = topSignal
        self.topRecoverySuggestion = topRecoverySuggestion
        self.hasFreshInsights = hasFreshInsights
    }
}

public struct DashboardReferralSummary: Sendable {
    public let applicationsWithReceivedReferral: Int
    public let interviewingApplicationsWithReferral: Int
    public let receivedReferralAttempts: Int
    public let interviewReferralRate: Double

    public init(
        applicationsWithReceivedReferral: Int,
        interviewingApplicationsWithReferral: Int,
        receivedReferralAttempts: Int,
        interviewReferralRate: Double
    ) {
        self.applicationsWithReceivedReferral = applicationsWithReceivedReferral
        self.interviewingApplicationsWithReferral = interviewingApplicationsWithReferral
        self.receivedReferralAttempts = receivedReferralAttempts
        self.interviewReferralRate = interviewReferralRate
    }
}

public struct DashboardAnalyticsResult {
    public let scope: AnalyticsComparisonScope
    public let currentSnapshot: DashboardSnapshot
    public let previousSnapshot: DashboardSnapshot
    public let funnel: [DashboardStatusCount]
    public let timeInStage: [DashboardTimeInStage]
    public let cadenceHeatmap: [DashboardHeatmapCell]
    public let salaryDistribution: [DashboardSalaryBin]
    public let averageExpectedComp: Double?
    public let averageOfferedComp: Double?
    public let currentChecklist: DashboardChecklistSnapshot
    public let previousChecklist: DashboardChecklistSnapshot
    public let rejectionSummary: DashboardRejectionSummary
    public let referralSummary: DashboardReferralSummary
    public let averageMatchScore: Double?
    public let staleMatchCount: Int
    public let goalProgress: [DashboardGoalProgress]
    public let activeCycle: JobSearchCycle?
    public let previousCycle: JobSearchCycle?
    public let fxUsedFallback: Bool
    public let missingSalaryConversionCount: Int
    public let comparisonLabel: String

    public init(
        scope: AnalyticsComparisonScope,
        currentSnapshot: DashboardSnapshot,
        previousSnapshot: DashboardSnapshot,
        funnel: [DashboardStatusCount],
        timeInStage: [DashboardTimeInStage],
        cadenceHeatmap: [DashboardHeatmapCell],
        salaryDistribution: [DashboardSalaryBin],
        averageExpectedComp: Double?,
        averageOfferedComp: Double?,
        currentChecklist: DashboardChecklistSnapshot,
        previousChecklist: DashboardChecklistSnapshot,
        rejectionSummary: DashboardRejectionSummary,
        referralSummary: DashboardReferralSummary,
        averageMatchScore: Double?,
        staleMatchCount: Int,
        goalProgress: [DashboardGoalProgress],
        activeCycle: JobSearchCycle?,
        previousCycle: JobSearchCycle?,
        fxUsedFallback: Bool,
        missingSalaryConversionCount: Int,
        comparisonLabel: String
    ) {
        self.scope = scope
        self.currentSnapshot = currentSnapshot
        self.previousSnapshot = previousSnapshot
        self.funnel = funnel
        self.timeInStage = timeInStage
        self.cadenceHeatmap = cadenceHeatmap
        self.salaryDistribution = salaryDistribution
        self.averageExpectedComp = averageExpectedComp
        self.averageOfferedComp = averageOfferedComp
        self.currentChecklist = currentChecklist
        self.previousChecklist = previousChecklist
        self.rejectionSummary = rejectionSummary
        self.referralSummary = referralSummary
        self.averageMatchScore = averageMatchScore
        self.staleMatchCount = staleMatchCount
        self.goalProgress = goalProgress
        self.activeCycle = activeCycle
        self.previousCycle = previousCycle
        self.fxUsedFallback = fxUsedFallback
        self.missingSalaryConversionCount = missingSalaryConversionCount
        self.comparisonLabel = comparisonLabel
    }
}

public final class DashboardAnalyticsService: @unchecked Sendable {
    private let exchangeRateService: ExchangeRateProviding
    private let calendar: Calendar

    public init(
        exchangeRateService: ExchangeRateProviding = ExchangeRateService.shared,
        calendar: Calendar = .current
    ) {
        self.exchangeRateService = exchangeRateService
        self.calendar = calendar
    }

    public func analyze(
        applications: [JobApplication],
        cycles: [JobSearchCycle],
        goals: [SearchGoal],
        scope: AnalyticsComparisonScope,
        baseCurrency: Currency,
        rejectionLearningSnapshot: RejectionLearningSnapshot? = nil,
        currentResumeRevisionID: UUID? = nil,
        matchPreferences: JobMatchPreferences = JobMatchPreferences(),
        referenceDate: Date = Date()
    ) async -> DashboardAnalyticsResult {
        let cycleTimeline = cycles.sorted { $0.startDate < $1.startDate }
        let activeCycle = cycleTimeline.last(where: \.isActive)
        let previousCycle = activeCycle.flatMap { active in
            cycleTimeline.last(where: { $0.id != active.id && $0.startDate < active.startDate })
        }

        let scopedApps = applicationsForScope(
            scope,
            applications: applications,
            activeCycle: activeCycle,
            previousCycle: previousCycle,
            referenceDate: referenceDate
        )

        let currentSnapshot = snapshot(for: scopedApps.current)
        let previousSnapshot = snapshot(for: scopedApps.previous)
        let funnel = makeFunnel(for: scopedApps.current)
        let timeInStage = makeTimeInStage(for: scopedApps.current, referenceDate: referenceDate)
        let cadenceHeatmap = makeCadenceHeatmap(for: scopedApps.current, referenceDate: referenceDate)
        let currentChecklist = makeChecklistSnapshot(for: scopedApps.current, referenceDate: referenceDate)
        let previousChecklist = makeChecklistSnapshot(for: scopedApps.previous, referenceDate: referenceDate)
        let rejectionSummary = makeRejectionSummary(
            for: scopedApps.current,
            rejectionLearningSnapshot: rejectionLearningSnapshot,
            referenceDate: referenceDate
        )
        let referralSummary = makeReferralSummary(for: scopedApps.current)
        let matchAnalytics = makeMatchAnalytics(
            for: scopedApps.current,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )

        let salaryAnalytics = await makeSalaryAnalytics(
            for: scopedApps.current,
            baseCurrency: baseCurrency
        )

        let goalProgress = makeGoalProgress(
            goals: goals,
            activeCycle: activeCycle,
            referenceDate: referenceDate
        )

        let comparisonLabel: String
        switch scope {
        case .thisWeek:
            comparisonLabel = "vs last week"
        case .thisMonth:
            comparisonLabel = "vs last month"
        case .currentCycle:
            comparisonLabel = previousCycle == nil ? "No previous cycle" : "vs \(previousCycle?.name ?? "previous cycle")"
        }

        return DashboardAnalyticsResult(
            scope: scope,
            currentSnapshot: currentSnapshot,
            previousSnapshot: previousSnapshot,
            funnel: funnel,
            timeInStage: timeInStage,
            cadenceHeatmap: cadenceHeatmap,
            salaryDistribution: salaryAnalytics.bins,
            averageExpectedComp: salaryAnalytics.averageExpectedComp,
            averageOfferedComp: salaryAnalytics.averageOfferedComp,
            currentChecklist: currentChecklist,
            previousChecklist: previousChecklist,
            rejectionSummary: rejectionSummary,
            referralSummary: referralSummary,
            averageMatchScore: matchAnalytics.averageScore,
            staleMatchCount: matchAnalytics.staleCount,
            goalProgress: goalProgress,
            activeCycle: activeCycle,
            previousCycle: previousCycle,
            fxUsedFallback: salaryAnalytics.fxUsedFallback,
            missingSalaryConversionCount: salaryAnalytics.missingConversionCount,
            comparisonLabel: comparisonLabel
        )
    }

    private func applicationsForScope(
        _ scope: AnalyticsComparisonScope,
        applications: [JobApplication],
        activeCycle: JobSearchCycle?,
        previousCycle: JobSearchCycle?,
        referenceDate: Date
    ) -> (current: [JobApplication], previous: [JobApplication]) {
        switch scope {
        case .thisWeek:
            let currentInterval = weekInterval(containing: referenceDate)
            let previousStart = calendar.date(byAdding: .weekOfYear, value: -1, to: currentInterval.start) ?? currentInterval.start
            let previousInterval = DateInterval(start: previousStart, duration: currentInterval.duration)
            return (
                applications.filter { app in application(app, wasSubmittedIn: currentInterval) },
                applications.filter { app in application(app, wasSubmittedIn: previousInterval) }
            )
        case .thisMonth:
            let currentInterval = monthInterval(containing: referenceDate)
            let previousStart = calendar.date(byAdding: .month, value: -1, to: currentInterval.start) ?? currentInterval.start
            let previousInterval = DateInterval(start: previousStart, end: currentInterval.start)
            return (
                applications.filter { app in application(app, wasSubmittedIn: currentInterval) },
                applications.filter { app in application(app, wasSubmittedIn: previousInterval) }
            )
        case .currentCycle:
            return (
                applications.filter { $0.cycle?.id == activeCycle?.id },
                applications.filter {
                    $0.cycle?.id == previousCycle?.id ||
                    $0.originCycle?.id == previousCycle?.id
                }
            )
        }
    }

    private func makeChecklistSnapshot(
        for applications: [JobApplication],
        referenceDate: Date
    ) -> DashboardChecklistSnapshot {
        let checklistTasks = applications.flatMap(\.sortedChecklistTasks)
        let completedItems = checklistTasks.filter(\.isCompleted).count
        let openItems = checklistTasks.count - completedItems
        let startOfToday = calendar.startOfDay(for: referenceDate)
        let overdueItems = checklistTasks.filter { task in
            guard !task.isCompleted, let dueDate = task.dueDate else { return false }
            return dueDate < startOfToday
        }.count

        return DashboardChecklistSnapshot(
            totalItems: checklistTasks.count,
            completedItems: completedItems,
            openItems: openItems,
            overdueItems: overdueItems,
            completionRate: checklistTasks.isEmpty ? 0 : Double(completedItems) / Double(checklistTasks.count)
        )
    }

    private func makeRejectionSummary(
        for applications: [JobApplication],
        rejectionLearningSnapshot: RejectionLearningSnapshot?,
        referenceDate: Date
    ) -> DashboardRejectionSummary {
        let rejectedApplications = applications.filter { $0.status == .rejected }
        let loggedRejections = rejectedApplications.filter { $0.latestRejectionLog != nil }
        let missingLogCount = max(0, rejectedApplications.count - loggedRejections.count)
        let hasFreshInsights: Bool

        if let rejectionLearningSnapshot {
            hasFreshInsights =
                rejectionLearningSnapshot.rejectionCount >= 3 &&
                referenceDate.timeIntervalSince(rejectionLearningSnapshot.generatedAt) <= 30 * 86_400
        } else {
            hasFreshInsights = false
        }

        return DashboardRejectionSummary(
            rejectedApplications: rejectedApplications.count,
            loggedRejections: loggedRejections.count,
            missingLogCount: missingLogCount,
            topSignal: hasFreshInsights ? rejectionLearningSnapshot?.patternSignals.first : nil,
            topRecoverySuggestion: hasFreshInsights ? rejectionLearningSnapshot?.recoverySuggestions.first : nil,
            hasFreshInsights: hasFreshInsights
        )
    }

    private func makeMatchAnalytics(
        for applications: [JobApplication],
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> (averageScore: Double?, staleCount: Int) {
        let assessedApplications = applications.compactMap { application -> (JobApplication, JobMatchAssessment)? in
            guard let assessment = application.matchAssessment else { return nil }
            return (application, assessment)
        }

        let staleCount = assessedApplications.filter { application, assessment in
            JobMatchScoringService.isStale(
                assessment,
                application: application,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: preferences
            )
        }.count

        let freshScores = assessedApplications.compactMap { application, assessment -> Int? in
            guard assessment.status == .ready,
                  !JobMatchScoringService.isStale(
                    assessment,
                    application: application,
                    currentResumeRevisionID: currentResumeRevisionID,
                    preferences: preferences
                  ) else {
                return nil
            }
            return assessment.overallScore
        }

        guard !freshScores.isEmpty else { return (nil, staleCount) }
        let total = freshScores.reduce(0, +)
        return (Double(total) / Double(freshScores.count), staleCount)
    }

    private func snapshot(for applications: [JobApplication]) -> DashboardSnapshot {
        let nonSaved = applications.filter { $0.status != .saved && $0.status != .archived }
        let total = applications.count
        let active = nonSaved.count
        let submitted = applications.filter { $0.submittedAt != nil }.count
        let interviews = applications.filter { $0.status == .interviewing || $0.status == .offered }.count
        let offers = applications.filter { $0.status == .offered }.count
        let gotResponse = nonSaved.filter {
            $0.status == .interviewing || $0.status == .offered || $0.status == .rejected
        }.count
        let responseRate = nonSaved.isEmpty ? 0 : Double(gotResponse) / Double(nonSaved.count)

        return DashboardSnapshot(
            totalApplications: total,
            activeApplications: active,
            submittedApplications: submitted,
            interviewingApplications: interviews,
            offeredApplications: offers,
            responseRate: responseRate
        )
    }

    private func makeReferralSummary(for applications: [JobApplication]) -> DashboardReferralSummary {
        let referredApplications = applications.filter(\.hasReceivedReferral)
        let interviewingApplicationsWithReferral = referredApplications.filter { application in
            switch application.status {
            case .interviewing, .offered, .rejected:
                return true
            case .saved, .applied, .archived, .custom(_):
                return false
            }
        }.count

        let totalInterviewingApplications = applications.filter { application in
            switch application.status {
            case .interviewing, .offered, .rejected:
                return true
            case .saved, .applied, .archived, .custom(_):
                return false
            }
        }.count

        let receivedReferralAttempts = referredApplications.reduce(0) { partialResult, application in
            partialResult + application.sortedReferralAttempts.filter { $0.status == .received }.count
        }

        let interviewReferralRate: Double
        if totalInterviewingApplications == 0 {
            interviewReferralRate = 0
        } else {
            interviewReferralRate = Double(interviewingApplicationsWithReferral) / Double(totalInterviewingApplications)
        }

        return DashboardReferralSummary(
            applicationsWithReceivedReferral: referredApplications.count,
            interviewingApplicationsWithReferral: interviewingApplicationsWithReferral,
            receivedReferralAttempts: receivedReferralAttempts,
            interviewReferralRate: interviewReferralRate
        )
    }

    private func makeFunnel(for applications: [JobApplication]) -> [DashboardStatusCount] {
        let statuses: [ApplicationStatus] = [.saved, .applied, .interviewing, .offered, .rejected]
        return statuses.map { status in
            DashboardStatusCount(
                status: status,
                count: applications.filter { $0.status == status }.count
            )
        }
    }

    private func makeTimeInStage(
        for applications: [JobApplication],
        referenceDate: Date
    ) -> [DashboardTimeInStage] {
        let trackableStatuses: [ApplicationStatus] = [.applied, .interviewing, .offered]

        return trackableStatuses.compactMap { status in
            let matching = applications.filter { $0.status == status }
            guard !matching.isEmpty else { return nil }

            let totalDays = matching.reduce(0.0) { partialResult, application in
                let startDate = application.appliedDate ?? application.createdAt
                let days = max(0, referenceDate.timeIntervalSince(startDate) / 86_400)
                return partialResult + days
            }

            return DashboardTimeInStage(
                status: status,
                averageDays: totalDays / Double(matching.count)
            )
        }
    }

    private func makeCadenceHeatmap(
        for applications: [JobApplication],
        referenceDate: Date
    ) -> [DashboardHeatmapCell] {
        let endDate = calendar.startOfDay(for: referenceDate)
        guard let startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: startOfWeek(for: endDate)) else {
            return []
        }

        let submissions = applications.compactMap(\.submittedAt).filter { $0 >= startDate && $0 <= referenceDate }
        let weekStarts = (0..<12).compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: offset, to: startDate)
        }

        return weekStarts.flatMap { weekStart in
            (0..<7).map { weekdayIndex in
                let count = submissions.filter { submissionDate in
                    calendar.isDate(submissionDate, equalTo: weekStart, toGranularity: .weekOfYear) &&
                    weekdayIndexForHeatmap(submissionDate) == weekdayIndex
                }.count
                return DashboardHeatmapCell(weekStart: weekStart, weekdayIndex: weekdayIndex, count: count)
            }
        }
    }

    private func makeGoalProgress(
        goals: [SearchGoal],
        activeCycle: JobSearchCycle?,
        referenceDate: Date
    ) -> [DashboardGoalProgress] {
        guard let activeCycle else { return [] }

        let cycleGoals = goals
            .filter { $0.cycle?.id == activeCycle.id && !$0.isArchived }
            .sorted {
                if $0.cadence != $1.cadence {
                    return $0.cadence == .weekly && $1.cadence == .monthly
                }
                return $0.metric.displayName.localizedCaseInsensitiveCompare($1.metric.displayName) == .orderedAscending
            }

        return cycleGoals.map { goal in
            let interval = periodInterval(for: goal.cadence, referenceDate: referenceDate)
            let progress = progress(for: goal.metric, in: activeCycle, during: interval)
            return DashboardGoalProgress(
                goalID: goal.id,
                title: goal.title,
                metric: goal.metric,
                cadence: goal.cadence,
                progress: progress,
                target: goal.targetValue,
                periodLabel: periodLabel(for: goal.cadence, referenceDate: referenceDate)
            )
        }
    }

    private func progress(
        for metric: SearchGoalMetric,
        in cycle: JobSearchCycle,
        during interval: DateInterval
    ) -> Int {
        let applications = cycle.applications ?? []
        switch metric {
        case .applicationsSubmitted:
            return applications.filter { application($0, wasSubmittedIn: interval) }.count
        case .interviewsBooked:
            return applications
                .flatMap { $0.interviewLogs ?? [] }
                .filter { interval.contains($0.date) }
                .count
        case .offersReceived:
            return applications.filter {
                $0.status == .offered && interval.contains($0.updatedAt)
            }.count
        }
    }

    private func makeSalaryAnalytics(
        for applications: [JobApplication],
        baseCurrency: Currency
    ) async -> (bins: [DashboardSalaryBin], averageExpectedComp: Double?, averageOfferedComp: Double?, fxUsedFallback: Bool, missingConversionCount: Int) {
        var postedValues: [Double] = []
        var expectedValues: [Double] = []
        var offeredValues: [Double] = []
        var usedFallback = false
        var missingConversionCount = 0
        var rateCache: [String: ExchangeRateService.ConversionResult?] = [:]

        for application in applications {
            if let postedMidpoint = midpoint(min: application.postedTotalCompMin, max: application.postedTotalCompMax) {
                if let conversion = await convertValue(
                    postedMidpoint,
                    from: application.currency,
                    to: baseCurrency,
                    on: application.submittedAt ?? application.updatedAt,
                    rateCache: &rateCache
                ) {
                    postedValues.append(conversion.amount)
                    usedFallback = usedFallback || conversion.usedFallback
                } else {
                    missingConversionCount += 1
                }
            }

            if let expectedMidpoint = midpoint(min: application.expectedTotalCompMin, max: application.expectedTotalCompMax) {
                if let conversion = await convertValue(
                    expectedMidpoint,
                    from: application.currency,
                    to: baseCurrency,
                    on: application.updatedAt,
                    rateCache: &rateCache
                ) {
                    expectedValues.append(conversion.amount)
                    usedFallback = usedFallback || conversion.usedFallback
                } else {
                    missingConversionCount += 1
                }
            }

            if let offerTotal = application.offerTotalComp {
                if let conversion = await convertValue(
                    offerTotal,
                    from: application.currency,
                    to: baseCurrency,
                    on: application.updatedAt,
                    rateCache: &rateCache
                ) {
                    offeredValues.append(conversion.amount)
                    usedFallback = usedFallback || conversion.usedFallback
                } else {
                    missingConversionCount += 1
                }
            }
        }

        return (
            bins: salaryBins(from: postedValues, currency: baseCurrency),
            averageExpectedComp: average(of: expectedValues),
            averageOfferedComp: average(of: offeredValues),
            fxUsedFallback: usedFallback,
            missingConversionCount: missingConversionCount
        )
    }

    private func convertValue(
        _ amount: Int,
        from: Currency,
        to: Currency,
        on date: Date,
        rateCache: inout [String: ExchangeRateService.ConversionResult?]
    ) async -> ExchangeRateService.ConversionResult? {
        if from == to {
            return ExchangeRateService.ConversionResult(amount: Double(amount), rateDate: date, usedFallback: false)
        }

        let dayKey = normalizedDayKey(for: date)
        let cacheKey = "\(from.rawValue)-\(to.rawValue)-\(dayKey)"
        let rateConversion: ExchangeRateService.ConversionResult?

        if let cached = rateCache[cacheKey] {
            rateConversion = cached
        } else {
            let fetched = await exchangeRateService.convert(amount: 1, from: from, to: to, on: date)
            rateCache[cacheKey] = fetched
            rateConversion = fetched
        }

        guard let rateConversion else { return nil }

        return ExchangeRateService.ConversionResult(
            amount: rateConversion.amount * Double(amount),
            rateDate: rateConversion.rateDate,
            usedFallback: rateConversion.usedFallback
        )
    }

    private func normalizedDayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: calendar.startOfDay(for: date))
    }

    private func salaryBins(from values: [Double], currency: Currency) -> [DashboardSalaryBin] {
        guard let minValue = values.min(), let maxValue = values.max() else { return [] }
        let binCount = min(6, max(1, values.count))

        if minValue == maxValue {
            let label = currency.format(Int(minValue.rounded()))
            return [DashboardSalaryBin(label: label, lowerBound: minValue, upperBound: maxValue, count: values.count)]
        }

        let width = (maxValue - minValue) / Double(binCount)
        return (0..<binCount).map { index in
            let lower = minValue + (Double(index) * width)
            let upper = index == binCount - 1 ? maxValue : lower + width
            let count = values.filter { value in
                if index == binCount - 1 {
                    return value >= lower && value <= upper
                }
                return value >= lower && value < upper
            }.count
            let label = "\(currency.format(Int(lower.rounded()))) - \(currency.format(Int(upper.rounded())))"
            return DashboardSalaryBin(label: label, lowerBound: lower, upperBound: upper, count: count)
        }
    }

    private func midpoint(min: Int?, max: Int?) -> Int? {
        switch (min, max) {
        case let (min?, max?):
            return Int(((Double(min) + Double(max)) / 2).rounded())
        case let (min?, nil):
            return min
        case let (nil, max?):
            return max
        case (nil, nil):
            return nil
        }
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func application(_ application: JobApplication, wasSubmittedIn interval: DateInterval) -> Bool {
        guard let submittedAt = application.submittedAt else { return false }
        return interval.contains(submittedAt)
    }

    private func weekInterval(containing date: Date) -> DateInterval {
        let start = startOfWeek(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    private func monthInterval(containing date: Date) -> DateInterval {
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
        let end = calendar.date(byAdding: .month, value: 1, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    private func periodInterval(for cadence: SearchGoalCadence, referenceDate: Date) -> DateInterval {
        switch cadence {
        case .weekly:
            return weekInterval(containing: referenceDate)
        case .monthly:
            return monthInterval(containing: referenceDate)
        }
    }

    private func periodLabel(for cadence: SearchGoalCadence, referenceDate: Date) -> String {
        switch cadence {
        case .weekly:
            let interval = weekInterval(containing: referenceDate)
            let formatter = DateIntervalFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .none
            return formatter.string(from: interval.start, to: calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end)
        case .monthly:
            return referenceDate.formatted(.dateTime.month(.wide).year())
        }
    }

    private func startOfWeek(for date: Date) -> Date {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func weekdayIndexForHeatmap(_ date: Date) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let zeroBasedWeekday = weekday - 1
        let firstWeekdayIndex = calendar.firstWeekday - 1
        return (zeroBasedWeekday - firstWeekdayIndex + 7) % 7
    }
}
