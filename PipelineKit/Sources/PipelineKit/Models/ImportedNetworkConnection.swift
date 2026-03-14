import Foundation
import SwiftData

@Model
public final class ImportedNetworkConnection {
    public var id: UUID = UUID()
    private var providerRawValue: String = NetworkImportProvider.linkedInCSV.rawValue
    private var statusRawValue: String = ImportedNetworkConnectionStatus.available.rawValue
    public var providerRowID: String = ""
    public var fullName: String = ""
    public var email: String?
    public var companyName: String?
    public var title: String?
    public var linkedInURL: String?
    public var connectedOn: Date?
    public var normalizedFullName: String = ""
    public var normalizedCompanyName: String = ""
    public var notes: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var batch: NetworkImportBatch?

    @Relationship(deleteRule: .nullify)
    public var linkedContact: Contact?

    @Relationship(deleteRule: .cascade, inverse: \ReferralAttempt.importedConnection)
    public var referralAttempts: [ReferralAttempt]?

    public var provider: NetworkImportProvider {
        get { NetworkImportProvider(rawValue: providerRawValue) ?? .linkedInCSV }
        set { providerRawValue = newValue.rawValue }
    }

    public var status: ImportedNetworkConnectionStatus {
        get { ImportedNetworkConnectionStatus(rawValue: statusRawValue) ?? .available }
        set { statusRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        provider: NetworkImportProvider = .linkedInCSV,
        providerRowID: String,
        fullName: String,
        email: String? = nil,
        companyName: String? = nil,
        title: String? = nil,
        linkedInURL: String? = nil,
        connectedOn: Date? = nil,
        notes: String? = nil,
        batch: NetworkImportBatch? = nil,
        linkedContact: Contact? = nil,
        referralAttempts: [ReferralAttempt]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.providerRawValue = provider.rawValue
        self.statusRawValue = linkedContact == nil ? ImportedNetworkConnectionStatus.available.rawValue : ImportedNetworkConnectionStatus.promoted.rawValue
        self.providerRowID = providerRowID
        self.fullName = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.email = CompanyProfile.normalizedText(email)
        self.companyName = CompanyProfile.normalizedText(companyName)
        self.title = CompanyProfile.normalizedText(title)
        self.linkedInURL = CompanyProfile.normalizedURLString(linkedInURL)
        self.connectedOn = connectedOn
        self.normalizedFullName = Self.normalizedFullName(from: fullName)
        self.normalizedCompanyName = CompanyProfile.normalizedName(from: companyName ?? "")
        self.notes = CompanyProfile.normalizedText(notes)
        self.batch = batch
        self.linkedContact = linkedContact
        self.referralAttempts = referralAttempts
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayCompanyName: String {
        companyName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? companyName! : "Independent"
    }

    public var hasEmail: Bool {
        email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var lookupKey: String {
        providerRowID.isEmpty ? "\(normalizedFullName)|\(normalizedCompanyName)" : providerRowID
    }

    public func refreshNormalizedFields() {
        normalizedFullName = Self.normalizedFullName(from: fullName)
        normalizedCompanyName = CompanyProfile.normalizedName(from: companyName ?? "")
    }

    public func markPromoted(to contact: Contact?) {
        linkedContact = contact
        status = contact == nil ? .available : .promoted
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public static func normalizedFullName(from value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
