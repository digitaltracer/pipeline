import Foundation

public struct InterviewQuestionBankEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let applicationID: UUID
    public let activityID: UUID
    public let debriefID: UUID
    public let companyName: String
    public let normalizedCompanyName: String
    public let role: String
    public let normalizedRole: String
    public let interviewStage: InterviewStage?
    public let question: String
    public let normalizedQuestion: String
    public let category: InterviewQuestionCategory
    public let answerNotes: String?
    public let interviewerHint: String?
    public let confidence: Int?
    public let occurredAt: Date
}

public struct InterviewLearningContext: Sendable {
    public let questionBankEntries: [InterviewQuestionBankEntry]
    public let categoryCounts: [(category: InterviewQuestionCategory, count: Int)]
    public let companyCategoryCounts: [(companyName: String, category: InterviewQuestionCategory, count: Int)]
    public let stageCounts: [(stage: InterviewStage, count: Int)]
    public let confidenceTrend: [Int]
    public let interviewCount: Int
    public let debriefCount: Int
    public let questionCount: Int
    public let companyCount: Int

    public var learningSummary: String {
        var sections: [String] = []

        if !questionBankEntries.isEmpty {
            let questions = questionBankEntries.prefix(12).map { entry in
                var line = "- [\(entry.category.displayName)] \(entry.question)"
                line += " (\(entry.companyName)"
                if let stage = entry.interviewStage {
                    line += ", \(stage.displayName)"
                }
                line += ")"
                if let answerNotes = entry.answerNotes, !answerNotes.isEmpty {
                    line += " :: \(answerNotes)"
                }
                return line
            }
            sections.append("Question Bank:\n" + questions.joined(separator: "\n"))
        }

        if !categoryCounts.isEmpty {
            let categorySummary = categoryCounts
                .prefix(5)
                .map { "\($0.category.displayName): \($0.count)" }
                .joined(separator: ", ")
            sections.append("Category Frequency: \(categorySummary)")
        }

        if !companyCategoryCounts.isEmpty {
            let companySummary = companyCategoryCounts
                .prefix(5)
                .map { "\($0.companyName) -> \($0.category.displayName) x\($0.count)" }
                .joined(separator: ", ")
            sections.append("Company Patterns: \(companySummary)")
        }

        if !confidenceTrend.isEmpty {
            let trend = confidenceTrend.map(String.init).joined(separator: ", ")
            sections.append("Recent Confidence Scores: \(trend)")
        }

        return sections.joined(separator: "\n\n")
    }
}

public struct PersonalizedInterviewPrepContext: Sendable {
    public let boostedQuestions: [InterviewQuestionBankEntry]
    public let learningSummary: String
}

public struct InterviewLearningContextBuilder {
    public init() {}

    public func build(from applications: [JobApplication]) -> InterviewLearningContext {
        let questionBankEntries = questionBankEntries(from: applications)
        let categoryCounts = Dictionary(grouping: questionBankEntries, by: \.category)
            .map { (category: $0.key, count: $0.value.count) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.category.displayName < rhs.category.displayName
            }

        let companyCategoryCounts = Dictionary(grouping: questionBankEntries) { entry in
            "\(entry.normalizedCompanyName)|\(entry.category.rawValue)"
        }
        .compactMap { key, entries -> (String, InterviewQuestionCategory, Int)? in
            guard let first = entries.first else { return nil }
            return (first.companyName, first.category, entries.count)
        }
        .sorted { lhs, rhs in
            if lhs.2 != rhs.2 {
                return lhs.2 > rhs.2
            }
            if lhs.0 != rhs.0 {
                return lhs.0 < rhs.0
            }
            return lhs.1.displayName < rhs.1.displayName
        }

        let stageCounts = Dictionary(grouping: questionBankEntries.compactMap { entry -> InterviewStage? in
            entry.interviewStage
        }, by: { $0 })
        .map { (stage: $0.key, count: $0.value.count) }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count {
                return lhs.count > rhs.count
            }
            return lhs.stage.sortOrder < rhs.stage.sortOrder
        }

        let confidenceTrend = applications
            .flatMap(\.sortedInterviewActivities)
            .compactMap { $0.debrief?.confidence }
            .suffix(8)

        return InterviewLearningContext(
            questionBankEntries: questionBankEntries,
            categoryCounts: categoryCounts,
            companyCategoryCounts: companyCategoryCounts,
            stageCounts: stageCounts,
            confidenceTrend: Array(confidenceTrend),
            interviewCount: applications.reduce(into: 0) { $0 += $1.sortedInterviewActivities.count },
            debriefCount: applications.reduce(into: 0) { total, application in
                total += application.sortedInterviewActivities.filter(\.hasDebrief).count
            },
            questionCount: questionBankEntries.count,
            companyCount: Set(questionBankEntries.map(\.normalizedCompanyName)).count
        )
    }

    public func personalizedPrepContext(
        for application: JobApplication,
        in applications: [JobApplication],
        limit: Int = 8
    ) -> PersonalizedInterviewPrepContext {
        let context = build(from: applications)
        let targetCompany = CompanyProfile.normalizedName(from: application.companyName)
        let targetRole = CompanyProfile.normalizedRoleTitle(application.role)
        let targetStage = application.sortedInterviewActivities.first?.interviewStage ?? application.interviewStage

        let boostedQuestions = context.questionBankEntries
            .sorted { lhs, rhs in
                let lhsScore = relevanceScore(
                    for: lhs,
                    targetCompany: targetCompany,
                    targetRole: targetRole,
                    targetStage: targetStage
                )
                let rhsScore = relevanceScore(
                    for: rhs,
                    targetCompany: targetCompany,
                    targetRole: targetRole,
                    targetStage: targetStage
                )
                if lhsScore != rhsScore {
                    return lhsScore > rhsScore
                }
                return lhs.occurredAt > rhs.occurredAt
            }
            .reduce(into: [InterviewQuestionBankEntry]()) { result, entry in
                guard !result.contains(where: { $0.normalizedQuestion == entry.normalizedQuestion }) else { return }
                result.append(entry)
            }

        return PersonalizedInterviewPrepContext(
            boostedQuestions: Array(boostedQuestions.prefix(limit)),
            learningSummary: context.learningSummary
        )
    }

    public func questionBankEntries(from applications: [JobApplication]) -> [InterviewQuestionBankEntry] {
        applications.flatMap { application in
            application.sortedInterviewActivities.flatMap { activity -> [InterviewQuestionBankEntry] in
                guard let debrief = activity.debrief else { return [] }
                return debrief.sortedQuestionEntries.compactMap { question in
                    let normalizedPrompt = normalize(question.prompt)
                    guard !normalizedPrompt.isEmpty else { return nil }
                    return InterviewQuestionBankEntry(
                        id: "\(debrief.id.uuidString)-\(question.id.uuidString)",
                        applicationID: application.id,
                        activityID: activity.id,
                        debriefID: debrief.id,
                        companyName: application.companyName,
                        normalizedCompanyName: CompanyProfile.normalizedName(from: application.companyName),
                        role: application.role,
                        normalizedRole: CompanyProfile.normalizedRoleTitle(application.role),
                        interviewStage: activity.interviewStage,
                        question: question.prompt,
                        normalizedQuestion: normalizedPrompt,
                        category: question.category,
                        answerNotes: question.answerNotes,
                        interviewerHint: question.interviewerHint,
                        confidence: debrief.confidence,
                        occurredAt: activity.occurredAt
                    )
                }
            }
        }
    }

    public func fallbackInsights(from context: InterviewLearningContext) -> InterviewLearningSnapshot {
        let strengths = context.categoryCounts.prefix(2).map {
            "You have the most interview history in \($0.category.displayName.lowercased()) questions."
        }
        let growthAreas = context.categoryCounts.suffix(min(2, context.categoryCounts.count)).map {
            "You have less repetition in \($0.category.displayName.lowercased()) questions, so targeted practice may help."
        }
        let recurringThemes = context.stageCounts.prefix(3).map {
            "\($0.stage.displayName) appears \($0.count)x in your logged question bank."
        }
        let companyPatterns = context.companyCategoryCounts.prefix(3).map {
            "\($0.companyName) leaned on \($0.category.displayName.lowercased()) questions \($0.count)x."
        }
        let recommendedFocusAreas = Array((strengths + growthAreas).prefix(4))

        return InterviewLearningSnapshot(
            strengths: strengths,
            growthAreas: growthAreas,
            recurringThemes: recurringThemes,
            companyPatterns: companyPatterns,
            recommendedFocusAreas: recommendedFocusAreas,
            interviewCount: context.interviewCount,
            debriefCount: context.debriefCount,
            questionCount: context.questionCount,
            companyCount: context.companyCount,
            generatedAt: Date()
        )
    }

    private func relevanceScore(
        for entry: InterviewQuestionBankEntry,
        targetCompany: String,
        targetRole: String,
        targetStage: InterviewStage?
    ) -> Int {
        var score = 0

        if entry.normalizedCompanyName == targetCompany {
            score += 5
        }

        if let targetStage, entry.interviewStage == targetStage {
            score += 4
        }

        score += roleSimilarityScore(lhs: entry.normalizedRole, rhs: targetRole)

        if let confidence = entry.confidence {
            score += confidence
        }

        return score
    }

    private func roleSimilarityScore(lhs: String, rhs: String) -> Int {
        let ignoredTokens: Set<String> = ["engineer", "developer", "software", "senior", "staff", "lead", "principal"]
        let lhsTokens = Set(lhs.split(separator: " ").map(String.init)).subtracting(ignoredTokens)
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init)).subtracting(ignoredTokens)
        let overlap = lhsTokens.intersection(rhsTokens).count
        return overlap * 2
    }

    private func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
