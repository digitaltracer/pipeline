import Foundation
import SwiftData

@Model
public final class ApplicationContactLink {
    public var id: UUID = UUID()
    private var roleRawValue: String = ContactRole.recruiter.rawValue
    public var isPrimary: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?
    public var contact: Contact?

    public var role: ContactRole {
        get { ContactRole(rawValue: roleRawValue) }
        set { roleRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        application: JobApplication? = nil,
        contact: Contact? = nil,
        role: ContactRole = .recruiter,
        isPrimary: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.application = application
        self.contact = contact
        self.roleRawValue = role.rawValue
        self.isPrimary = isPrimary
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }
}
