import Foundation
import SwiftData

@Model
public final class InterviewLearningSnapshot {
    public var id: UUID = UUID()
    public var strengths: [String] = []
    public var growthAreas: [String] = []
    public var recurringThemes: [String] = []
    public var companyPatterns: [String] = []
    public var recommendedFocusAreas: [String] = []
    public var interviewCount: Int = 0
    public var debriefCount: Int = 0
    public var questionCount: Int = 0
    public var companyCount: Int = 0
    public var generatedAt: Date = Date()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        strengths: [String] = [],
        growthAreas: [String] = [],
        recurringThemes: [String] = [],
        companyPatterns: [String] = [],
        recommendedFocusAreas: [String] = [],
        interviewCount: Int = 0,
        debriefCount: Int = 0,
        questionCount: Int = 0,
        companyCount: Int = 0,
        generatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.strengths = Self.normalized(strengths)
        self.growthAreas = Self.normalized(growthAreas)
        self.recurringThemes = Self.normalized(recurringThemes)
        self.companyPatterns = Self.normalized(companyPatterns)
        self.recommendedFocusAreas = Self.normalized(recommendedFocusAreas)
        self.interviewCount = max(0, interviewCount)
        self.debriefCount = max(0, debriefCount)
        self.questionCount = max(0, questionCount)
        self.companyCount = max(0, companyCount)
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func update(
        strengths: [String],
        growthAreas: [String],
        recurringThemes: [String],
        companyPatterns: [String],
        recommendedFocusAreas: [String],
        interviewCount: Int,
        debriefCount: Int,
        questionCount: Int,
        companyCount: Int,
        generatedAt: Date = Date()
    ) {
        self.strengths = Self.normalized(strengths)
        self.growthAreas = Self.normalized(growthAreas)
        self.recurringThemes = Self.normalized(recurringThemes)
        self.companyPatterns = Self.normalized(companyPatterns)
        self.recommendedFocusAreas = Self.normalized(recommendedFocusAreas)
        self.interviewCount = max(0, interviewCount)
        self.debriefCount = max(0, debriefCount)
        self.questionCount = max(0, questionCount)
        self.companyCount = max(0, companyCount)
        self.generatedAt = generatedAt
        self.updatedAt = Date()
    }

    private static func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
