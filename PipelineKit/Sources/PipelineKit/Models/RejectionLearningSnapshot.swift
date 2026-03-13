import Foundation
import SwiftData

@Model
public final class RejectionLearningSnapshot {
    public var id: UUID = UUID()
    public var patternSignals: [String] = []
    public var targetingSignals: [String] = []
    public var processSignals: [String] = []
    public var recoverySuggestions: [String] = []
    public var stageCounts: [String] = []
    public var reasonCounts: [String] = []
    public var feedbackSourceCounts: [String] = []
    public var rejectionCount: Int = 0
    public var explicitFeedbackCount: Int = 0
    public var generatedAt: Date = Date()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public init(
        id: UUID = UUID(),
        patternSignals: [String] = [],
        targetingSignals: [String] = [],
        processSignals: [String] = [],
        recoverySuggestions: [String] = [],
        stageCounts: [String] = [],
        reasonCounts: [String] = [],
        feedbackSourceCounts: [String] = [],
        rejectionCount: Int = 0,
        explicitFeedbackCount: Int = 0,
        generatedAt: Date = Date(),
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.patternSignals = Self.normalized(patternSignals)
        self.targetingSignals = Self.normalized(targetingSignals)
        self.processSignals = Self.normalized(processSignals)
        self.recoverySuggestions = Self.normalized(recoverySuggestions)
        self.stageCounts = Self.normalized(stageCounts)
        self.reasonCounts = Self.normalized(reasonCounts)
        self.feedbackSourceCounts = Self.normalized(feedbackSourceCounts)
        self.rejectionCount = max(0, rejectionCount)
        self.explicitFeedbackCount = max(0, explicitFeedbackCount)
        self.generatedAt = generatedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func update(
        patternSignals: [String],
        targetingSignals: [String],
        processSignals: [String],
        recoverySuggestions: [String],
        stageCounts: [String],
        reasonCounts: [String],
        feedbackSourceCounts: [String],
        rejectionCount: Int,
        explicitFeedbackCount: Int,
        generatedAt: Date = Date()
    ) {
        self.patternSignals = Self.normalized(patternSignals)
        self.targetingSignals = Self.normalized(targetingSignals)
        self.processSignals = Self.normalized(processSignals)
        self.recoverySuggestions = Self.normalized(recoverySuggestions)
        self.stageCounts = Self.normalized(stageCounts)
        self.reasonCounts = Self.normalized(reasonCounts)
        self.feedbackSourceCounts = Self.normalized(feedbackSourceCounts)
        self.rejectionCount = max(0, rejectionCount)
        self.explicitFeedbackCount = max(0, explicitFeedbackCount)
        self.generatedAt = generatedAt
        self.updatedAt = Date()
    }

    private static func normalized(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
