import Foundation
import SwiftData

@Model
public final class InterviewDebrief {
    public var id: UUID = UUID()
    public var confidence: Int = 3
    public var whatWentWell: String?
    public var wouldDoDifferently: String?
    public var overallNotes: String?
    public var createdTaskIDs: [UUID] = []
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var activity: ApplicationActivity?

    @Relationship(deleteRule: .cascade, inverse: \InterviewQuestionEntry.debrief)
    public var questionEntries: [InterviewQuestionEntry]?

    public init(
        id: UUID = UUID(),
        confidence: Int = 3,
        whatWentWell: String? = nil,
        wouldDoDifferently: String? = nil,
        overallNotes: String? = nil,
        createdTaskIDs: [UUID] = [],
        activity: ApplicationActivity? = nil,
        questionEntries: [InterviewQuestionEntry]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.confidence = Self.clampedConfidence(confidence)
        self.whatWentWell = Self.normalized(whatWentWell)
        self.wouldDoDifferently = Self.normalized(wouldDoDifferently)
        self.overallNotes = Self.normalized(overallNotes)
        self.createdTaskIDs = createdTaskIDs
        self.activity = activity
        self.questionEntries = questionEntries
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sortedQuestionEntries: [InterviewQuestionEntry] {
        (questionEntries ?? []).sorted { lhs, rhs in
            if lhs.orderIndex != rhs.orderIndex {
                return lhs.orderIndex < rhs.orderIndex
            }

            if lhs.createdAt != rhs.createdAt {
                return lhs.createdAt < rhs.createdAt
            }

            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    public func update(
        confidence: Int,
        whatWentWell: String?,
        wouldDoDifferently: String?,
        overallNotes: String?
    ) {
        self.confidence = Self.clampedConfidence(confidence)
        self.whatWentWell = Self.normalized(whatWentWell)
        self.wouldDoDifferently = Self.normalized(wouldDoDifferently)
        self.overallNotes = Self.normalized(overallNotes)
        updateTimestamp()
    }

    public func appendCreatedTaskID(_ taskID: UUID) {
        guard !createdTaskIDs.contains(taskID) else { return }
        createdTaskIDs.append(taskID)
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    private static func clampedConfidence(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
