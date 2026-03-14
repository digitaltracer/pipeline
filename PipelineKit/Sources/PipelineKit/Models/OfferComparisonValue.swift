import Foundation
import SwiftData

@Model
public final class OfferComparisonValue {
    public var id: UUID = UUID()
    public var applicationID: UUID = UUID()
    public var displayText: String?
    public var score: Int?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var factor: OfferComparisonFactor?

    public init(
        id: UUID = UUID(),
        applicationID: UUID,
        displayText: String? = nil,
        score: Int? = nil,
        factor: OfferComparisonFactor? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.applicationID = applicationID
        self.displayText = Self.normalizedText(displayText)
        self.score = Self.clampedScore(score)
        self.factor = factor
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func update(displayText: String?, score: Int?) {
        self.displayText = Self.normalizedText(displayText)
        self.score = Self.clampedScore(score)
        updatedAt = Date()
        factor?.updateTimestamp()
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func clampedScore(_ value: Int?) -> Int? {
        guard let value else { return nil }
        return min(max(value, 1), 5)
    }
}
