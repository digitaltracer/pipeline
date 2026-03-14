import Foundation
import SwiftData

@Model
public final class OfferComparisonWorksheet {
    public var id: UUID = UUID()
    public var title: String = "Offer Comparison"
    public var selectedApplicationIDs: [UUID] = []
    public var knownApplicationIDs: [UUID] = []

    public var recommendationText: String?
    public var recommendationProvider: String?
    public var recommendationModel: String?
    public var recommendationCitationsJSON: String?
    public var recommendationGeneratedAt: Date?

    public var negotiationText: String?
    public var negotiationProvider: String?
    public var negotiationModel: String?
    public var negotiationCitationsJSON: String?
    public var negotiationGeneratedAt: Date?

    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \OfferComparisonFactor.worksheet)
    public var factors: [OfferComparisonFactor]?

    public init(
        id: UUID = UUID(),
        title: String = "Offer Comparison",
        selectedApplicationIDs: [UUID] = [],
        knownApplicationIDs: [UUID] = [],
        recommendationText: String? = nil,
        recommendationProvider: String? = nil,
        recommendationModel: String? = nil,
        recommendationCitationsJSON: String? = nil,
        recommendationGeneratedAt: Date? = nil,
        negotiationText: String? = nil,
        negotiationProvider: String? = nil,
        negotiationModel: String? = nil,
        negotiationCitationsJSON: String? = nil,
        negotiationGeneratedAt: Date? = nil,
        factors: [OfferComparisonFactor]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.selectedApplicationIDs = selectedApplicationIDs.uniquedPreservingOrder()
        self.knownApplicationIDs = knownApplicationIDs.uniquedPreservingOrder()
        self.recommendationText = recommendationText
        self.recommendationProvider = recommendationProvider
        self.recommendationModel = recommendationModel
        self.recommendationCitationsJSON = recommendationCitationsJSON
        self.recommendationGeneratedAt = recommendationGeneratedAt
        self.negotiationText = negotiationText
        self.negotiationProvider = negotiationProvider
        self.negotiationModel = negotiationModel
        self.negotiationCitationsJSON = negotiationCitationsJSON
        self.negotiationGeneratedAt = negotiationGeneratedAt
        self.factors = factors
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sortedFactors: [OfferComparisonFactor] {
        (factors ?? []).sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public var recommendationCitations: [AIWebSearchCitation] {
        decodeCitations(from: recommendationCitationsJSON)
    }

    public var negotiationCitations: [AIWebSearchCitation] {
        decodeCitations(from: negotiationCitationsJSON)
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public func setSelectedApplicationIDs(_ ids: [UUID]) {
        let normalized = ids.uniquedPreservingOrder()
        guard selectedApplicationIDs != normalized else { return }
        selectedApplicationIDs = normalized
        updateTimestamp()
    }

    public func setKnownApplicationIDs(_ ids: [UUID]) {
        let normalized = ids.uniquedPreservingOrder()
        guard knownApplicationIDs != normalized else { return }
        knownApplicationIDs = normalized
        updateTimestamp()
    }

    public func addFactor(_ factor: OfferComparisonFactor) {
        if factors == nil {
            factors = []
        }
        if factors?.contains(where: { $0.id == factor.id }) != true {
            factors?.append(factor)
        }
        factor.worksheet = self
        updateTimestamp()
    }

    public func setRecommendationOutput(
        text: String?,
        provider: String?,
        model: String?,
        citations: [AIWebSearchCitation],
        generatedAt: Date = Date()
    ) {
        recommendationText = Self.normalizedText(text)
        recommendationProvider = Self.normalizedText(provider)
        recommendationModel = Self.normalizedText(model)
        recommendationCitationsJSON = Self.encodeCitations(citations)
        recommendationGeneratedAt = recommendationText == nil ? nil : generatedAt
        updateTimestamp()
    }

    public func setNegotiationOutput(
        text: String?,
        provider: String?,
        model: String?,
        citations: [AIWebSearchCitation],
        generatedAt: Date = Date()
    ) {
        negotiationText = Self.normalizedText(text)
        negotiationProvider = Self.normalizedText(provider)
        negotiationModel = Self.normalizedText(model)
        negotiationCitationsJSON = Self.encodeCitations(citations)
        negotiationGeneratedAt = negotiationText == nil ? nil : generatedAt
        updateTimestamp()
    }

    private func decodeCitations(from json: String?) -> [AIWebSearchCitation] {
        guard let json,
              let data = json.data(using: .utf8),
              let citations = try? JSONDecoder().decode([AIWebSearchCitation].self, from: data) else {
            return []
        }
        return citations
    }

    private static func encodeCitations(_ citations: [AIWebSearchCitation]) -> String? {
        guard !citations.isEmpty,
              let data = try? JSONEncoder().encode(citations),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    private static func normalizedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}
