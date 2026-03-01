import Foundation
import SwiftData

public enum AIModelRateSource: String, Codable, CaseIterable, Sendable, Identifiable {
    case seeded = "seeded"
    case user = "user"

    public var id: String { rawValue }
}

@Model
public final class AIModelRate {
    public var id: UUID = UUID()
    public var providerID: String = ""
    public var model: String = ""
    public var inputUSDPerMillion: Double = 0
    public var outputUSDPerMillion: Double = 0
    public var updatedAt: Date = Date()
    public var sourceRawValue: String = AIModelRateSource.seeded.rawValue

    public init(
        id: UUID = UUID(),
        providerID: String,
        model: String,
        inputUSDPerMillion: Double,
        outputUSDPerMillion: Double,
        updatedAt: Date = Date(),
        source: AIModelRateSource = .seeded
    ) {
        self.id = id
        self.providerID = providerID
        self.model = model
        self.inputUSDPerMillion = inputUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
        self.updatedAt = updatedAt
        self.sourceRawValue = source.rawValue
    }

    public var source: AIModelRateSource {
        get { AIModelRateSource(rawValue: sourceRawValue) ?? .seeded }
        set {
            sourceRawValue = newValue.rawValue
            updatedAt = Date()
        }
    }
}
