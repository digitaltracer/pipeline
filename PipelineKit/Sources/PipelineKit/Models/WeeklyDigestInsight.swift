import Foundation
import SwiftData

@Model
public final class WeeklyDigestInsight {
    public var id: UUID = UUID()
    private var sourceKindRawValue: String = WeeklyDigestInsightSourceKind.rule.rawValue
    public var sortOrder: Int = 0
    public var title: String = ""
    public var body: String = ""
    public var evidenceText: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var snapshot: WeeklyDigestSnapshot?

    public var sourceKind: WeeklyDigestInsightSourceKind {
        get { WeeklyDigestInsightSourceKind(rawValue: sourceKindRawValue) ?? .rule }
        set {
            guard sourceKindRawValue != newValue.rawValue else { return }
            sourceKindRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }

    public init(
        id: UUID = UUID(),
        sourceKind: WeeklyDigestInsightSourceKind = .rule,
        sortOrder: Int,
        title: String,
        body: String,
        evidenceText: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.sourceKindRawValue = sourceKind.rawValue
        self.sortOrder = sortOrder
        self.title = title
        self.body = body
        self.evidenceText = evidenceText
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
