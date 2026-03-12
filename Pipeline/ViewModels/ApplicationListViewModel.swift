import Foundation
import SwiftData
import SwiftUI
import PipelineKit

@Observable
final class ApplicationListViewModel {
    var searchText: String = ""
    var selectedFilter: SidebarFilter = .all
    var sortOrder: SortOrder = .updatedAt
    var matchScoreFilter: MatchScoreFilter = .all

    enum SortOrder: String, CaseIterable {
        case updatedAt = "Recently Updated"
        case createdAt = "Recently Added"
        case companyName = "Company Name"
        case appliedDate = "Applied Date"
        case priority = "Priority"
        case matchScore = "Match Score"
    }

    enum MatchScoreFilter: String, CaseIterable {
        case all = "All Scores"
        case high = "80+"
        case medium = "60-79"
        case low = "<60"
        case unscored = "Unscored"
        case stale = "Stale"
    }

    // MARK: - Statistics

    func calculateStats(from applications: [JobApplication]) -> ApplicationStats {
        let total = applications.count
        let applied = applications.filter { $0.status == .applied || $0.status == .interviewing || $0.status == .offered || $0.status == .rejected }.count
        let interviewing = applications.filter { $0.status == .interviewing }.count
        let offers = applications.filter { $0.status == .offered }.count
        let rejected = applications.filter { $0.status == .rejected }.count

        let responseRate: Double
        if applied > 0 {
            responseRate = Double(interviewing + offers + rejected) / Double(applied) * 100
        } else {
            responseRate = 0
        }

        return ApplicationStats(
            total: total,
            applied: applied,
            interviewing: interviewing,
            offers: offers,
            rejected: rejected,
            responseRate: responseRate
        )
    }

    // MARK: - Filtering

    func filterApplications(
        _ applications: [JobApplication],
        currentResumeRevisionID: UUID? = nil,
        matchPreferences: JobMatchPreferences = JobMatchPreferences(),
        includeInAllApplications: (JobApplication) -> Bool = { _ in true }
    ) -> [JobApplication] {
        var filtered = applications

        // Apply status filter
        if selectedFilter == .all {
            filtered = filtered.filter(includeInAllApplications)
        } else if let status = selectedFilter.status {
            filtered = filtered.filter { $0.status == status }
        }

        // Apply search filter
        if !searchText.isEmpty {
            let lowercasedSearch = searchText.lowercased()
            filtered = filtered.filter { app in
                app.companyName.lowercased().contains(lowercasedSearch) ||
                app.role.lowercased().contains(lowercasedSearch) ||
                app.location.lowercased().contains(lowercasedSearch)
            }
        }

        filtered = filtered.filter { application in
            matchesScoreFilter(
                application,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: matchPreferences
            )
        }

        // Apply sorting
        filtered = sortApplications(
            filtered,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )

        return filtered
    }

    private func sortApplications(_ applications: [JobApplication]) -> [JobApplication] {
        sortApplications(
            applications,
            currentResumeRevisionID: nil,
            preferences: JobMatchPreferences()
        )
    }

    private func sortApplications(
        _ applications: [JobApplication],
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> [JobApplication] {
        switch sortOrder {
        case .updatedAt:
            return applications.sorted { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            return applications.sorted { $0.createdAt > $1.createdAt }
        case .companyName:
            return applications.sorted { $0.companyName < $1.companyName }
        case .appliedDate:
            return applications.sorted { ($0.appliedDate ?? .distantPast) > ($1.appliedDate ?? .distantPast) }
        case .priority:
            return applications.sorted { $0.priority.sortOrder < $1.priority.sortOrder }
        case .matchScore:
            return applications.sorted {
                compareMatchOrdering(
                    lhs: $0,
                    rhs: $1,
                    currentResumeRevisionID: currentResumeRevisionID,
                    preferences: preferences
                )
            }
        }
    }

    // MARK: - Status Counts

    func statusCounts(
        from applications: [JobApplication],
        includeInAllApplications: (JobApplication) -> Bool = { _ in true }
    ) -> [SidebarFilter: Int] {
        var counts: [SidebarFilter: Int] = [:]

        counts[.all] = applications.filter(includeInAllApplications).count

        for filter in SidebarFilter.allCases {
            if let status = filter.status {
                counts[filter] = applications.filter { $0.status == status }.count
            }
        }

        return counts
    }

    private func matchesScoreFilter(
        _ application: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Bool {
        switch matchScoreFilter {
        case .all:
            return true
        case .high:
            return freshScore(for: application, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences).map { $0 >= 80 } ?? false
        case .medium:
            return freshScore(for: application, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences).map { (60...79).contains($0) } ?? false
        case .low:
            return freshScore(for: application, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences).map { $0 < 60 } ?? false
        case .unscored:
            return application.matchAssessment == nil
        case .stale:
            guard let assessment = application.matchAssessment else { return false }
            return JobMatchScoringService.isStale(
                assessment,
                application: application,
                currentResumeRevisionID: currentResumeRevisionID,
                preferences: preferences
            )
        }
    }

    private func freshScore(
        for application: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Int? {
        guard let assessment = application.matchAssessment,
              assessment.status == .ready,
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

    private func compareMatchOrdering(
        lhs: JobApplication,
        rhs: JobApplication,
        currentResumeRevisionID: UUID?,
        preferences: JobMatchPreferences
    ) -> Bool {
        let lhsScore = freshScore(for: lhs, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences) ?? -1
        let rhsScore = freshScore(for: rhs, currentResumeRevisionID: currentResumeRevisionID, preferences: preferences) ?? -1

        if lhsScore != rhsScore {
            return lhsScore > rhsScore
        }

        return lhs.updatedAt > rhs.updatedAt
    }
}

// MARK: - Application Stats

struct ApplicationStats {
    let total: Int
    let applied: Int
    let interviewing: Int
    let offers: Int
    let rejected: Int
    let responseRate: Double

    var formattedResponseRate: String {
        String(format: "%.0f%%", responseRate)
    }
}
