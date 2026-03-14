import Foundation
import SwiftData

@Model
public final class NetworkImportBatch {
    public var id: UUID = UUID()
    private var providerRawValue: String = NetworkImportProvider.linkedInCSV.rawValue
    public var sourceFileName: String = ""
    public var importedAt: Date = Date()
    public var importedCount: Int = 0
    public var updatedCount: Int = 0
    public var skippedCount: Int = 0
    public var errorCount: Int = 0
    public var notes: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \ImportedNetworkConnection.batch)
    public var connections: [ImportedNetworkConnection]?

    public var provider: NetworkImportProvider {
        get { NetworkImportProvider(rawValue: providerRawValue) ?? .linkedInCSV }
        set { providerRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        provider: NetworkImportProvider = .linkedInCSV,
        sourceFileName: String,
        importedAt: Date = Date(),
        importedCount: Int = 0,
        updatedCount: Int = 0,
        skippedCount: Int = 0,
        errorCount: Int = 0,
        notes: String? = nil,
        connections: [ImportedNetworkConnection]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.sourceFileName = sourceFileName
        self.importedAt = importedAt
        self.importedCount = importedCount
        self.updatedCount = updatedCount
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.notes = CompanyProfile.normalizedText(notes)
        self.connections = connections
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var sortedConnections: [ImportedNetworkConnection] {
        (connections ?? []).sorted { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
        }
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
