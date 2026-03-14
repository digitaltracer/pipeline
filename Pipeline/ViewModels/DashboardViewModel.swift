import Foundation
import PipelineKit

@MainActor
@Observable
final class DashboardViewModel {
    struct SummaryCard: Identifiable {
        let id: String
        let title: String
        let value: String
        let deltaText: String
        let deltaColorName: String
        let icon: String
    }

    var selectedScope: AnalyticsComparisonScope = .thisWeek
    var analytics: DashboardAnalyticsResult?
    var isRefreshing = false
    var lastRefreshToken = ""

    private let analyticsService: DashboardAnalyticsService
    private var activeRefreshToken: String?

    init(analyticsService: DashboardAnalyticsService = DashboardAnalyticsService()) {
        self.analyticsService = analyticsService
    }

    func refresh(
        token: String,
        applications: [JobApplication],
        cycles: [JobSearchCycle],
        goals: [SearchGoal],
        baseCurrency: Currency,
        rejectionLearningSnapshot: RejectionLearningSnapshot?,
        currentResumeRevisionID: UUID?,
        matchPreferences: JobMatchPreferences
    ) async {
        lastRefreshToken = token
        activeRefreshToken = token
        isRefreshing = true

        let result = await analyticsService.analyze(
            applications: applications,
            cycles: cycles,
            goals: goals,
            scope: selectedScope,
            baseCurrency: baseCurrency,
            rejectionLearningSnapshot: rejectionLearningSnapshot,
            currentResumeRevisionID: currentResumeRevisionID,
            matchPreferences: matchPreferences
        )

        guard activeRefreshToken == token, !Task.isCancelled else { return }

        analytics = result
        activeRefreshToken = nil
        isRefreshing = false
    }

    func cancelRefresh() {
        activeRefreshToken = nil
        isRefreshing = false
    }

    var summaryCards: [SummaryCard] {
        guard let analytics else { return [] }

        return [
            SummaryCard(
                id: "submitted",
                title: "Submitted",
                value: "\(analytics.currentSnapshot.submittedApplications)",
                deltaText: deltaString(
                    current: analytics.currentSnapshot.submittedApplications,
                    previous: analytics.previousSnapshot.submittedApplications
                ),
                deltaColorName: deltaColorName(
                    current: Double(analytics.currentSnapshot.submittedApplications),
                    previous: Double(analytics.previousSnapshot.submittedApplications)
                ),
                icon: "paperplane.fill"
            ),
            SummaryCard(
                id: "interviews",
                title: "Interviews",
                value: "\(analytics.currentSnapshot.interviewingApplications)",
                deltaText: deltaString(
                    current: analytics.currentSnapshot.interviewingApplications,
                    previous: analytics.previousSnapshot.interviewingApplications
                ),
                deltaColorName: deltaColorName(
                    current: Double(analytics.currentSnapshot.interviewingApplications),
                    previous: Double(analytics.previousSnapshot.interviewingApplications)
                ),
                icon: "person.2.fill"
            ),
            SummaryCard(
                id: "offers",
                title: "Offers",
                value: "\(analytics.currentSnapshot.offeredApplications)",
                deltaText: deltaString(
                    current: analytics.currentSnapshot.offeredApplications,
                    previous: analytics.previousSnapshot.offeredApplications
                ),
                deltaColorName: deltaColorName(
                    current: Double(analytics.currentSnapshot.offeredApplications),
                    previous: Double(analytics.previousSnapshot.offeredApplications)
                ),
                icon: "gift.fill"
            ),
            SummaryCard(
                id: "referral-rate",
                title: "Referral Wins",
                value: percentString(analytics.referralSummary.interviewReferralRate),
                deltaText: "\(analytics.referralSummary.interviewingApplicationsWithReferral) interview\(analytics.referralSummary.interviewingApplicationsWithReferral == 1 ? "" : "s")",
                deltaColorName: analytics.referralSummary.interviewingApplicationsWithReferral == 0 ? "secondary" : "positive",
                icon: "person.3.fill"
            ),
            SummaryCard(
                id: "response-rate",
                title: "Response Rate",
                value: percentString(analytics.currentSnapshot.responseRate),
                deltaText: deltaString(
                    current: analytics.currentSnapshot.responseRate,
                    previous: analytics.previousSnapshot.responseRate,
                    isPercent: true
                ),
                deltaColorName: deltaColorName(
                    current: analytics.currentSnapshot.responseRate,
                    previous: analytics.previousSnapshot.responseRate
                ),
                icon: "chart.line.uptrend.xyaxis"
            ),
            SummaryCard(
                id: "checklist-rate",
                title: "Checklist Rate",
                value: percentString(analytics.currentChecklist.completionRate),
                deltaText: deltaString(
                    current: analytics.currentChecklist.completionRate,
                    previous: analytics.previousChecklist.completionRate,
                    isPercent: true
                ),
                deltaColorName: deltaColorName(
                    current: analytics.currentChecklist.completionRate,
                    previous: analytics.previousChecklist.completionRate
                ),
                icon: "checklist"
            ),
            SummaryCard(
                id: "avg-match",
                title: "Avg Match",
                value: analytics.averageMatchScore.map(percentString) ?? "—",
                deltaText: analytics.staleMatchCount > 0 ? "\(analytics.staleMatchCount) stale" : "Fresh scores",
                deltaColorName: analytics.staleMatchCount > 0 ? "secondary" : "positive",
                icon: "bolt.badge.checkmark"
            )
        ]
    }

    func percentString(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    func currencyString(_ value: Double, currency: Currency) -> String {
        currency.format(Int(value.rounded()))
    }

    private func deltaString(current: Int, previous: Int) -> String {
        let delta = current - previous
        if delta == 0 {
            return "No change"
        }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    private func deltaString(current: Double, previous: Double, isPercent: Bool) -> String {
        let delta = current - previous
        if abs(delta) < 0.0001 {
            return "No change"
        }

        if isPercent {
            let points = Int((delta * 100).rounded())
            return points > 0 ? "+\(points) pts" : "\(points) pts"
        }

        let rounded = Int(delta.rounded())
        return rounded > 0 ? "+\(rounded)" : "\(rounded)"
    }

    private func deltaColorName(current: Double, previous: Double) -> String {
        if abs(current - previous) < 0.0001 {
            return "secondary"
        }
        return current >= previous ? "positive" : "negative"
    }
}
