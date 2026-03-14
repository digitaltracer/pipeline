import Foundation
import SwiftData

@Model
public final class ReferralAttempt {
    public var id: UUID = UUID()
    private var statusRawValue: String = ReferralAttemptStatus.asked.rawValue
    public var subject: String?
    public var body: String?
    public var askedAt: Date?
    public var statusUpdatedAt: Date = Date()
    public var followUpNeededAt: Date?
    public var notes: String?
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?
    public var importedConnection: ImportedNetworkConnection?
    public var contact: Contact?

    @Relationship(deleteRule: .nullify)
    public var sentEmailActivity: ApplicationActivity?

    public var status: ReferralAttemptStatus {
        get { ReferralAttemptStatus(rawValue: statusRawValue) ?? .asked }
        set {
            statusRawValue = newValue.rawValue
            statusUpdatedAt = Date()
        }
    }

    public init(
        id: UUID = UUID(),
        status: ReferralAttemptStatus = .asked,
        subject: String? = nil,
        body: String? = nil,
        askedAt: Date? = nil,
        statusUpdatedAt: Date = Date(),
        followUpNeededAt: Date? = nil,
        notes: String? = nil,
        application: JobApplication? = nil,
        importedConnection: ImportedNetworkConnection? = nil,
        contact: Contact? = nil,
        sentEmailActivity: ApplicationActivity? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.statusRawValue = status.rawValue
        self.subject = CompanyProfile.normalizedText(subject)
        self.body = CompanyProfile.normalizedText(body)
        self.askedAt = askedAt
        self.statusUpdatedAt = statusUpdatedAt
        self.followUpNeededAt = followUpNeededAt
        self.notes = CompanyProfile.normalizedText(notes)
        self.application = application
        self.importedConnection = importedConnection
        self.contact = contact
        self.sentEmailActivity = sentEmailActivity
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var displayName: String {
        contact?.fullName ?? importedConnection?.fullName ?? "Referral Contact"
    }

    public var hasSendableEmail: Bool {
        let email = contact?.email ?? importedConnection?.email
        return email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    public var targetCompanyName: String? {
        contact?.companyName ?? importedConnection?.companyName
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
