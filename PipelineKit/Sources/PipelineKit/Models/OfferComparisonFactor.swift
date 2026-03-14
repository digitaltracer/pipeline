import Foundation
import SwiftData

@Model
public final class OfferComparisonFactor {
    public var id: UUID = UUID()
    public var kindRawValue: String = OfferComparisonFactorKind.custom.rawValue
    public var title: String = ""
    public var weight: Int = 1
    public var sortOrder: Int = 0
    public var isEnabled: Bool = true
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var worksheet: OfferComparisonWorksheet?

    @Relationship(deleteRule: .cascade, inverse: \OfferComparisonValue.factor)
    public var values: [OfferComparisonValue]?

    public init(
        id: UUID = UUID(),
        kind: OfferComparisonFactorKind,
        title: String? = nil,
        weight: Int = 1,
        sortOrder: Int = 0,
        isEnabled: Bool = true,
        worksheet: OfferComparisonWorksheet? = nil,
        values: [OfferComparisonValue]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.title = (title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : kind.title)
        self.weight = max(weight, 1)
        self.sortOrder = sortOrder
        self.isEnabled = isEnabled
        self.worksheet = worksheet
        self.values = values
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var kind: OfferComparisonFactorKind {
        get { OfferComparisonFactorKind(rawValue: kindRawValue) ?? .custom }
        set {
            guard kindRawValue != newValue.rawValue else { return }
            kindRawValue = newValue.rawValue
            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || kind != .custom {
                title = newValue.title
            }
            updateTimestamp()
        }
    }

    public var sortedValues: [OfferComparisonValue] {
        (values ?? []).sorted { lhs, rhs in
            if lhs.applicationID != rhs.applicationID {
                return lhs.applicationID.uuidString < rhs.applicationID.uuidString
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func updateTimestamp() {
        updatedAt = Date()
        worksheet?.updateTimestamp()
    }

    public func rename(_ newTitle: String) {
        let normalized = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, title != normalized else { return }
        title = normalized
        updateTimestamp()
    }

    public func setWeight(_ value: Int) {
        let normalized = max(value, 1)
        guard weight != normalized else { return }
        weight = normalized
        updateTimestamp()
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        updateTimestamp()
    }

    public func value(for applicationID: UUID) -> OfferComparisonValue? {
        sortedValues.first(where: { $0.applicationID == applicationID })
    }

    public func upsertValue(
        applicationID: UUID,
        displayText: String?,
        score: Int?
    ) -> OfferComparisonValue {
        if let existing = value(for: applicationID) {
            existing.update(displayText: displayText, score: score)
            return existing
        }

        let value = OfferComparisonValue(
            applicationID: applicationID,
            displayText: displayText,
            score: score,
            factor: self
        )
        if values == nil {
            values = []
        }
        values?.append(value)
        updateTimestamp()
        return value
    }
}
