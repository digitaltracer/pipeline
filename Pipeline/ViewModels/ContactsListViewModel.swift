import Foundation
import SwiftData
import PipelineKit

struct ContactRow: Identifiable {
    let id: PersistentIdentifier
    let contact: Contact
    let fullName: String
    let initials: String
    let title: String?
    let relationship: String?
    let email: String?
    let displayCompanyName: String
    let linkedCount: Int
}

@Observable
final class ContactsListViewModel {
    var searchText: String = ""
    var debouncedSearchText: String = ""

    func filterContacts(_ contacts: [Contact]) -> [ContactRow] {
        let query = debouncedSearchText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let filtered: [Contact]
        if query.isEmpty {
            filtered = contacts
        } else {
            filtered = contacts.filter { contact in
                contact.fullName.lowercased().contains(query) ||
                (contact.companyName?.lowercased().contains(query) ?? false) ||
                (contact.email?.lowercased().contains(query) ?? false) ||
                (contact.relationship?.lowercased().contains(query) ?? false) ||
                (contact.linkedInURL?.lowercased().contains(query) ?? false)
            }
        }

        let sorted = filtered.sorted { lhs, rhs in
            let lhsName = lhs.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = rhs.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if lhsName.caseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }

        return sorted.map(Self.buildRow(from:))
    }

    static func buildRow(from contact: Contact) -> ContactRow {
        ContactRow(
            id: contact.persistentModelID,
            contact: contact,
            fullName: contact.fullName,
            initials: contact.initials,
            title: contact.title,
            relationship: contact.relationship,
            email: contact.email,
            displayCompanyName: contact.displayCompanyName,
            linkedCount: (contact.applicationLinks ?? []).count
        )
    }
}
