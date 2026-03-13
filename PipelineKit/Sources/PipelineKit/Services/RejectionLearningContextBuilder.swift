import Foundation

public struct RejectionLearningEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let applicationID: UUID
    public let activityID: UUID
    public let logID: UUID
    public let companyName: String
    public let normalizedCompanyName: String
    public let role: String
    public let normalizedRole: String
    public let source: Source
    public let platform: Platform
    public let stageCategory: RejectionStageCategory
    public let reasonCategory: RejectionReasonCategory
    public let feedbackSource: RejectionFeedbackSource
    public let feedbackText: String?
    public let candidateReflection: String?
    public let doNotReapply: Bool
    public let occurredAt: Date
}

public struct RejectionLearningContext: Sendable {
    public let entries: [RejectionLearningEntry]
    public let stageCounts: [(stage: RejectionStageCategory, count: Int)]
    public let reasonCounts: [(reason: RejectionReasonCategory, count: Int)]
    public let feedbackSourceCounts: [(source: RejectionFeedbackSource, count: Int)]
    public let sourceCounts: [(source: Source, count: Int)]
    public let platformCounts: [(platform: Platform, count: Int)]
    public let rejectionCount: Int
    public let explicitFeedbackCount: Int

    public var learningSummary: String {
        var sections: [String] = []

        if !entries.isEmpty {
            let entryLines = entries.prefix(14).map { entry in
                var line = "- \(entry.companyName) / \(entry.role) :: \(entry.stageCategory.displayName), \(entry.reasonCategory.displayName), \(entry.feedbackSource.displayName)"
                if let feedbackText = entry.feedbackText, !feedbackText.isEmpty {
                    line += " :: \(feedbackText)"
                }
                return line
            }
            sections.append("Rejection Logs:\n" + entryLines.joined(separator: "\n"))
        }

        if !stageCounts.isEmpty {
            sections.append("Stage Counts: " + stageCounts.prefix(5).map { "\($0.stage.displayName): \($0.count)" }.joined(separator: ", "))
        }

        if !reasonCounts.isEmpty {
            sections.append("Reason Counts: " + reasonCounts.prefix(5).map { "\($0.reason.displayName): \($0.count)" }.joined(separator: ", "))
        }

        if !sourceCounts.isEmpty {
            sections.append("Source Counts: " + sourceCounts.prefix(5).map { "\($0.source.displayName): \($0.count)" }.joined(separator: ", "))
        }

        return sections.joined(separator: "\n\n")
    }
}

public struct RejectionLearningContextBuilder {
    public init() {}

    public func build(from applications: [JobApplication]) -> RejectionLearningContext {
        let entries = rejectionEntries(from: applications)

        return RejectionLearningContext(
            entries: entries,
            stageCounts: count(entries.map(\.stageCategory)),
            reasonCounts: count(entries.map(\.reasonCategory)),
            feedbackSourceCounts: count(entries.map(\.feedbackSource)),
            sourceCounts: count(entries.map(\.source)),
            platformCounts: count(entries.map(\.platform)),
            rejectionCount: entries.count,
            explicitFeedbackCount: entries.filter { $0.feedbackSource == .explicit }.count
        )
    }

    public func rejectionEntries(from applications: [JobApplication]) -> [RejectionLearningEntry] {
        applications.flatMap { application in
            application.sortedRejectionActivities.compactMap { activity in
                guard let log = activity.rejectionLog else { return nil }
                return RejectionLearningEntry(
                    id: "\(application.id.uuidString)-\(activity.id.uuidString)-\(log.id.uuidString)",
                    applicationID: application.id,
                    activityID: activity.id,
                    logID: log.id,
                    companyName: application.companyName,
                    normalizedCompanyName: CompanyProfile.normalizedName(from: application.companyName),
                    role: application.role,
                    normalizedRole: CompanyProfile.normalizedRoleTitle(application.role),
                    source: application.source,
                    platform: application.platform,
                    stageCategory: log.stageCategory,
                    reasonCategory: log.reasonCategory,
                    feedbackSource: log.feedbackSource,
                    feedbackText: log.feedbackText,
                    candidateReflection: log.candidateReflection,
                    doNotReapply: log.doNotReapply,
                    occurredAt: activity.occurredAt
                )
            }
        }
    }

    private func count<Value: Hashable>(_ values: [Value]) -> [(Value, Int)] {
        Dictionary(grouping: values, by: { $0 })
            .map { ($0.key, $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 {
                    return lhs.1 > rhs.1
                }
                return String(describing: lhs.0) < String(describing: rhs.0)
            }
    }
}
