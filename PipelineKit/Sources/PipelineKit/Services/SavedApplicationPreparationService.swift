import Foundation

public struct SavedApplicationPreparationStatus: Equatable, Sendable {
    public let hasTailoredResume: Bool
    public let hasCoverLetter: Bool
    public let hasCompanyResearch: Bool

    public init(
        hasTailoredResume: Bool,
        hasCoverLetter: Bool,
        hasCompanyResearch: Bool
    ) {
        self.hasTailoredResume = hasTailoredResume
        self.hasCoverLetter = hasCoverLetter
        self.hasCompanyResearch = hasCompanyResearch
    }

    public var isReadyToApply: Bool {
        hasTailoredResume && hasCoverLetter && hasCompanyResearch
    }

    public var missingPreparationTitles: [String] {
        var titles: [String] = []
        if !hasTailoredResume {
            titles.append("Tailored resume")
        }
        if !hasCoverLetter {
            titles.append("Cover letter")
        }
        if !hasCompanyResearch {
            titles.append("Company research")
        }
        return titles
    }
}

public enum SavedApplicationPreparationService {
    public static func status(for application: JobApplication) -> SavedApplicationPreparationStatus {
        SavedApplicationPreparationStatus(
            hasTailoredResume: !application.sortedResumeSnapshots.isEmpty,
            hasCoverLetter: application.coverLetterDraft?.hasContent == true,
            hasCompanyResearch: application.company?.sortedResearchSnapshots.contains(where: { $0.runStatus != .failed }) == true
        )
    }
}
