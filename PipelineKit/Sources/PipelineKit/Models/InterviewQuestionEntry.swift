import Foundation
import SwiftData

@Model
public final class InterviewQuestionEntry {
    public var id: UUID = UUID()
    public var prompt: String = ""
    private var categoryRawValue: String = InterviewQuestionCategory.other.rawValue
    public var answerNotes: String?
    public var interviewerHint: String?
    public var orderIndex: Int = 0
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var debrief: InterviewDebrief?

    public init(
        id: UUID = UUID(),
        prompt: String,
        category: InterviewQuestionCategory,
        answerNotes: String? = nil,
        interviewerHint: String? = nil,
        orderIndex: Int = 0,
        debrief: InterviewDebrief? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryRawValue = category.rawValue
        self.answerNotes = Self.normalized(answerNotes)
        self.interviewerHint = Self.normalized(interviewerHint)
        self.orderIndex = orderIndex
        self.debrief = debrief
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var category: InterviewQuestionCategory {
        get { InterviewQuestionCategory(rawValue: categoryRawValue) }
        set {
            guard categoryRawValue != newValue.rawValue else { return }
            categoryRawValue = newValue.rawValue
            updateTimestamp()
        }
    }

    public var normalizedPrompt: String {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func update(
        prompt: String,
        category: InterviewQuestionCategory,
        answerNotes: String?,
        interviewerHint: String?,
        orderIndex: Int
    ) {
        self.prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        self.categoryRawValue = category.rawValue
        self.answerNotes = Self.normalized(answerNotes)
        self.interviewerHint = Self.normalized(interviewerHint)
        self.orderIndex = orderIndex
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
