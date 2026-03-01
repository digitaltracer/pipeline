import Foundation
import SwiftData

public enum DuplicateDetectionService {

    public struct DuplicateCheckResult: Sendable {
        public let isDuplicate: Bool
        public let matchedApplicationID: UUID?
        public let matchReason: String?

        public init(isDuplicate: Bool, matchedApplicationID: UUID? = nil, matchReason: String? = nil) {
            self.isDuplicate = isDuplicate
            self.matchedApplicationID = matchedApplicationID
            self.matchReason = matchReason
        }
    }

    /// Check for duplicate applications by URL (exact) then by company+role (case-insensitive).
    @MainActor
    public static func checkForDuplicate(
        url: String?,
        company: String?,
        role: String?,
        context: ModelContext
    ) -> DuplicateCheckResult {
        // 1. Exact URL match
        if let url, !url.isEmpty {
            let descriptor = FetchDescriptor<JobApplication>()
            if let allApps = try? context.fetch(descriptor) {
                if let match = allApps.first(where: { $0.jobURL == url }) {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchedApplicationID: match.id,
                        matchReason: "Exact URL match"
                    )
                }
            }
        }

        // 2. Company + role match (case-insensitive)
        if let company, !company.isEmpty, let role, !role.isEmpty {
            let companyLower = company.lowercased()
            let roleLower = role.lowercased()

            let descriptor = FetchDescriptor<JobApplication>()
            if let allApps = try? context.fetch(descriptor) {
                if let match = allApps.first(where: {
                    $0.companyName.lowercased() == companyLower &&
                    $0.role.lowercased() == roleLower
                }) {
                    return DuplicateCheckResult(
                        isDuplicate: true,
                        matchedApplicationID: match.id,
                        matchReason: "Same company and role"
                    )
                }
            }
        }

        return DuplicateCheckResult(isDuplicate: false)
    }
}
