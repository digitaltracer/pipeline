import Foundation
import PipelineKit

@Observable
final class DashboardViewModel {

    // MARK: - Data Types

    struct FunnelItem: Identifiable {
        let id = UUID()
        let status: ApplicationStatus
        let count: Int
    }

    struct WeeklyActivity: Identifiable {
        let id = UUID()
        let weekStart: Date
        let count: Int
    }

    struct TimeInStage: Identifiable {
        let id = UUID()
        let status: ApplicationStatus
        let averageDays: Double
    }

    // MARK: - Computed Stats

    var funnel: [FunnelItem] = []
    var weeklyActivity: [WeeklyActivity] = []
    var timeInStage: [TimeInStage] = []
    var totalApplications: Int = 0
    var activeApplications: Int = 0
    var responseRate: Double = 0
    var interviewRate: Double = 0
    var offerRate: Double = 0

    // MARK: - Refresh

    func refresh(applications: [JobApplication]) {
        totalApplications = applications.count
        computeFunnel(applications)
        computeWeeklyActivity(applications)
        computeTimeInStage(applications)
        computeRates(applications)
    }

    // MARK: - Funnel

    private func computeFunnel(_ applications: [JobApplication]) {
        let statuses: [ApplicationStatus] = [.saved, .applied, .interviewing, .offered, .rejected]
        funnel = statuses.map { status in
            FunnelItem(status: status, count: applications.filter { $0.status == status }.count)
        }
    }

    // MARK: - Weekly Activity

    private func computeWeeklyActivity(_ applications: [JobApplication]) {
        let calendar = Calendar.current
        let now = Date()

        // Last 8 weeks
        var weeks: [WeeklyActivity] = []
        for weekOffset in (0..<8).reversed() {
            guard let weekStart = calendar.date(byAdding: .weekOfYear, value: -weekOffset, to: now) else { continue }
            let startOfWeek = calendar.startOfWeek(for: weekStart)
            guard let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek) else { continue }

            let count = applications.filter { app in
                app.createdAt >= startOfWeek && app.createdAt < endOfWeek
            }.count

            weeks.append(WeeklyActivity(weekStart: startOfWeek, count: count))
        }

        weeklyActivity = weeks
    }

    // MARK: - Time in Stage

    private func computeTimeInStage(_ applications: [JobApplication]) {
        let trackableStatuses: [ApplicationStatus] = [.applied, .interviewing, .offered]

        timeInStage = trackableStatuses.compactMap { status in
            let matching = applications.filter { $0.status == status }
            guard !matching.isEmpty else { return nil }

            let totalDays = matching.reduce(0.0) { sum, app in
                let start = app.appliedDate ?? app.createdAt
                let days = Date().timeIntervalSince(start) / 86400
                return sum + days
            }

            return TimeInStage(
                status: status,
                averageDays: totalDays / Double(matching.count)
            )
        }
    }

    // MARK: - Rates

    private func computeRates(_ applications: [JobApplication]) {
        let nonSaved = applications.filter { $0.status != .saved && $0.status != .archived }
        activeApplications = nonSaved.count

        guard !nonSaved.isEmpty else {
            responseRate = 0
            interviewRate = 0
            offerRate = 0
            return
        }

        let total = Double(nonSaved.count)
        let gotResponse = nonSaved.filter {
            $0.status == .interviewing || $0.status == .offered || $0.status == .rejected
        }.count

        responseRate = Double(gotResponse) / total

        let interviewing = nonSaved.filter {
            $0.status == .interviewing || $0.status == .offered
        }.count
        interviewRate = Double(interviewing) / total

        let offered = nonSaved.filter { $0.status == .offered }.count
        offerRate = Double(offered) / total
    }
}

// MARK: - Calendar Extension

private extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        let components = dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return self.date(from: components) ?? date
    }
}
