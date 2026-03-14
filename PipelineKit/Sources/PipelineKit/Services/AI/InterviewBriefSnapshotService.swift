import Foundation

public struct InterviewBriefSnapshotContent: Sendable {
    public let talkingPoints: [String]
    public let interviewerHighlights: [String]
    public let mustAskQuestions: [String]
    public let companyResearchSummary: String
    public let prepDeepLink: String
    public let generatedAt: Date
    public let isFallback: Bool

    public init(
        talkingPoints: [String],
        interviewerHighlights: [String],
        mustAskQuestions: [String],
        companyResearchSummary: String,
        prepDeepLink: String,
        generatedAt: Date = Date(),
        isFallback: Bool = false
    ) {
        self.talkingPoints = talkingPoints
        self.interviewerHighlights = interviewerHighlights
        self.mustAskQuestions = mustAskQuestions
        self.companyResearchSummary = companyResearchSummary
        self.prepDeepLink = prepDeepLink
        self.generatedAt = generatedAt
        self.isFallback = isFallback
    }
}

public enum InterviewBriefSnapshotService {
    public static func generateSnapshot(
        provider: AIProvider,
        apiKey: String,
        model: String,
        application: JobApplication,
        activity: ApplicationActivity,
        notes: String,
        personalQuestionBankContext: String,
        learningSummary: String
    ) async throws -> InterviewBriefSnapshotContent {
        let result = try await InterviewPrepService.generatePrep(
            provider: provider,
            apiKey: apiKey,
            model: model,
            role: application.role,
            company: application.companyName,
            jobDescription: application.jobDescription ?? "",
            interviewStage: activity.interviewStage?.displayName ?? "",
            notes: notes,
            personalQuestionBankContext: personalQuestionBankContext,
            learningSummary: learningSummary
        )

        return InterviewBriefSnapshotContent(
            talkingPoints: Array(result.talkingPoints.prefix(4)),
            interviewerHighlights: interviewerHighlights(for: application, activity: activity),
            mustAskQuestions: Array(result.questionsToAsk.prefix(4)),
            companyResearchSummary: result.companyResearchSummary,
            prepDeepLink: PipelineDeepLinkService.interviewPrepURL(
                applicationID: application.id,
                activityID: activity.id
            ).absoluteString
        )
    }

    public static func fallbackSnapshot(
        application: JobApplication,
        activity: ApplicationActivity
    ) -> InterviewBriefSnapshotContent {
        let stage = activity.interviewStage?.displayName ?? "Interview"
        let talkingPoints = [
            "Review why \(application.companyName) is a fit for your \(application.role) experience.",
            "Prepare concise stories that match the \(stage.lowercased()) format."
        ]

        return InterviewBriefSnapshotContent(
            talkingPoints: talkingPoints,
            interviewerHighlights: interviewerHighlights(for: application, activity: activity),
            mustAskQuestions: [
                "What does success look like in the first 90 days?",
                "How does this team measure impact for this role?"
            ],
            companyResearchSummary: "Open Pipeline to review your saved company research, timeline notes, and interview prep materials.",
            prepDeepLink: PipelineDeepLinkService.interviewPrepURL(
                applicationID: application.id,
                activityID: activity.id
            ).absoluteString,
            isFallback: true
        )
    }

    private static func interviewerHighlights(
        for application: JobApplication,
        activity: ApplicationActivity
    ) -> [String] {
        var highlights: [String] = []

        if let contact = activity.contact {
            highlights.append(contact.fullName)
        }

        let interviewerLinks = application.sortedContactLinks
            .filter { $0.role == .interviewer }
            .compactMap(\.contact?.fullName)
        highlights.append(contentsOf: interviewerLinks)

        return Array(NSOrderedSet(array: highlights)) as? [String] ?? []
    }
}
