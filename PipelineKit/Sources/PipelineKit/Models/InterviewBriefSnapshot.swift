import Foundation
import SwiftData

@Model
public final class InterviewBriefSnapshot {
    public var id: UUID = UUID()
    public var applicationID: UUID = UUID()
    public var activityID: UUID = UUID()
    public var interviewDate: Date = Date()
    public var talkingPoints: [String] = []
    public var interviewerHighlights: [String] = []
    public var mustAskQuestions: [String] = []
    public var companyResearchSummary: String = ""
    public var prepDeepLink: String = ""
    public var generatedAt: Date = Date()
    public var isStale: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        applicationID: UUID,
        activityID: UUID,
        interviewDate: Date,
        talkingPoints: [String] = [],
        interviewerHighlights: [String] = [],
        mustAskQuestions: [String] = [],
        companyResearchSummary: String = "",
        prepDeepLink: String,
        generatedAt: Date = Date(),
        isStale: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.applicationID = applicationID
        self.activityID = activityID
        self.interviewDate = interviewDate
        self.talkingPoints = talkingPoints
        self.interviewerHighlights = interviewerHighlights
        self.mustAskQuestions = mustAskQuestions
        self.companyResearchSummary = companyResearchSummary
        self.prepDeepLink = prepDeepLink
        self.generatedAt = generatedAt
        self.isStale = isStale
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var notificationSummary: String {
        let segments = [
            talkingPoints.first,
            interviewerHighlights.first,
            mustAskQuestions.first
        ].compactMap { value in
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return trimmed.isEmpty ? nil : trimmed
        }

        if !segments.isEmpty {
            return segments.joined(separator: " • ")
        }

        let summary = companyResearchSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? "Open Pipeline for your interview brief and prep notes." : summary
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
