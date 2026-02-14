import Foundation
import SwiftData
import SwiftUI
import PipelineKit

@Observable
final class ApplicationListViewModel {
    var searchText: String = ""
    var selectedFilter: SidebarFilter = .all
    var sortOrder: SortOrder = .updatedAt

    enum SortOrder: String, CaseIterable {
        case updatedAt = "Recently Updated"
        case createdAt = "Recently Added"
        case companyName = "Company Name"
        case appliedDate = "Applied Date"
        case priority = "Priority"
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

    func filterApplications(_ applications: [JobApplication]) -> [JobApplication] {
        var filtered = applications

        // Apply status filter
        if let status = selectedFilter.status {
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

        // Apply sorting
        filtered = sortApplications(filtered)

        return filtered
    }

    private func sortApplications(_ applications: [JobApplication]) -> [JobApplication] {
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
        }
    }

    // MARK: - Status Counts

    func statusCounts(from applications: [JobApplication]) -> [SidebarFilter: Int] {
        var counts: [SidebarFilter: Int] = [:]

        counts[.all] = applications.count

        for filter in SidebarFilter.allCases {
            if let status = filter.status {
                counts[filter] = applications.filter { $0.status == status }.count
            }
        }

        return counts
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
