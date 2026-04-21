import Foundation
import SwiftData

public struct BrowserCapturedContact: Sendable, Equatable {
    public let fullName: String
    public let companyName: String?
    public let title: String?
    public let relationship: String?
    public let linkedInURL: String?
    public let role: ContactRole

    public init?(dictionary: [String: Any]?, fallbackCompanyName: String) {
        guard let dictionary else { return nil }

        let rawName = (dictionary["fullName"] as? String)
            ?? (dictionary["name"] as? String)
            ?? ""
        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        self.fullName = trimmedName

        let rawCompany = (dictionary["companyName"] as? String) ?? fallbackCompanyName
        self.companyName = Self.trimmedOrNil(rawCompany)
        self.title = Self.trimmedOrNil(dictionary["title"] as? String)
        self.relationship = Self.trimmedOrNil(dictionary["relationship"] as? String)
        self.linkedInURL = Self.trimmedOrNil(
            (dictionary["linkedInURL"] as? String)
                ?? (dictionary["linkedinURL"] as? String)
                ?? (dictionary["url"] as? String)
        )
        let rawRole = (dictionary["role"] as? String) ?? ""
        self.role = ContactRole(rawValue: rawRole)
    }

    public init(
        fullName: String,
        companyName: String? = nil,
        title: String? = nil,
        relationship: String? = nil,
        linkedInURL: String? = nil,
        role: ContactRole = .other
    ) {
        self.fullName = fullName
        self.companyName = companyName
        self.title = title
        self.relationship = relationship
        self.linkedInURL = linkedInURL
        self.role = role
    }

    private static func trimmedOrNil(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum BrowserCaptureContactService {
    @discardableResult
    public static func attach(
        _ captured: BrowserCapturedContact?,
        to application: JobApplication,
        in context: ModelContext
    ) throws -> ApplicationContactLink? {
        guard let captured else { return nil }

        let contact = try existingContact(matching: captured, in: context)
            ?? makeContact(from: captured, context: context)

        contact.mergeCompanyNameIfMissing(captured.companyName ?? application.companyName)
        if (contact.title?.isEmpty ?? true), let title = captured.title {
            contact.title = title
        }
        if (contact.relationship?.isEmpty ?? true), let relationship = captured.relationship {
            contact.relationship = relationship
        }
        if (contact.linkedInURL?.isEmpty ?? true), let linkedInURL = captured.linkedInURL {
            contact.linkedInURL = linkedInURL
        }
        contact.updateTimestamp()

        return upsertLink(
            contact: contact,
            role: captured.role,
            application: application,
            context: context
        )
    }

    private static func existingContact(
        matching captured: BrowserCapturedContact,
        in context: ModelContext
    ) throws -> Contact? {
        guard let lookupKey = Contact.normalizedLookupKey(
            name: captured.fullName,
            companyName: captured.companyName
        ) else { return nil }

        let contacts = try context.fetch(FetchDescriptor<Contact>())
        return contacts.first { existing in
            Contact.normalizedLookupKey(
                name: existing.fullName,
                companyName: existing.companyName
            ) == lookupKey
        }
    }

    private static func makeContact(
        from captured: BrowserCapturedContact,
        context: ModelContext
    ) -> Contact {
        let contact = Contact(
            fullName: captured.fullName,
            companyName: captured.companyName,
            title: captured.title,
            relationship: captured.relationship,
            linkedInURL: captured.linkedInURL
        )
        context.insert(contact)
        return contact
    }

    private static func upsertLink(
        contact: Contact,
        role: ContactRole,
        application: JobApplication,
        context: ModelContext
    ) -> ApplicationContactLink {
        if let existing = application.contactLinks?.first(where: { $0.contact?.id == contact.id }) {
            existing.role = role
            existing.updateTimestamp()
            application.updateTimestamp()
            return existing
        }

        let link = ApplicationContactLink(
            application: application,
            contact: contact,
            role: role
        )
        context.insert(link)
        application.addContactLink(link)
        return link
    }
}
