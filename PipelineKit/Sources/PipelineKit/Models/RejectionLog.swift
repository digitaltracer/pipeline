import Foundation
import SwiftData

@Model
public final class RejectionLog {
    public var id: UUID = UUID()
    private var stageCategoryRawValue: String = RejectionStageCategory.unknown.rawValue
    private var reasonCategoryRawValue: String = RejectionReasonCategory.unknown.rawValue
    private var feedbackSourceRawValue: String = RejectionFeedbackSource.none.rawValue
    public var feedbackText: String?
    public var candidateReflection: String?
    public var doNotReapply: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var activity: ApplicationActivity?

    public var stageCategory: RejectionStageCategory {
        get { RejectionStageCategory(rawValue: stageCategoryRawValue) ?? .unknown }
        set {
            guard stageCategoryRawValue != newValue.rawValue else { return }
            stageCategoryRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var reasonCategory: RejectionReasonCategory {
        get { RejectionReasonCategory(rawValue: reasonCategoryRawValue) ?? .unknown }
        set {
            guard reasonCategoryRawValue != newValue.rawValue else { return }
            reasonCategoryRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    public var feedbackSource: RejectionFeedbackSource {
        get { RejectionFeedbackSource(rawValue: feedbackSourceRawValue) ?? .none }
        set {
            guard feedbackSourceRawValue != newValue.rawValue else { return }
            feedbackSourceRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    public init(
        id: UUID = UUID(),
        stageCategory: RejectionStageCategory = .unknown,
        reasonCategory: RejectionReasonCategory = .unknown,
        feedbackSource: RejectionFeedbackSource = .none,
        feedbackText: String? = nil,
        candidateReflection: String? = nil,
        doNotReapply: Bool = false,
        activity: ApplicationActivity? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.stageCategoryRawValue = stageCategory.rawValue
        self.reasonCategoryRawValue = reasonCategory.rawValue
        self.feedbackSourceRawValue = feedbackSource.rawValue
        self.feedbackText = Self.normalized(feedbackText)
        self.candidateReflection = Self.normalized(candidateReflection)
        self.doNotReapply = doNotReapply
        self.activity = activity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func update(
        stageCategory: RejectionStageCategory,
        reasonCategory: RejectionReasonCategory,
        feedbackSource: RejectionFeedbackSource,
        feedbackText: String?,
        candidateReflection: String?,
        doNotReapply: Bool
    ) {
        self.stageCategory = stageCategory
        self.reasonCategory = reasonCategory
        self.feedbackSource = feedbackSource
        self.feedbackText = Self.normalized(feedbackText)
        self.candidateReflection = Self.normalized(candidateReflection)
        self.doNotReapply = doNotReapply
        updatedAt = Date()
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
