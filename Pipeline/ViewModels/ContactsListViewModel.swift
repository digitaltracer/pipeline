import Foundation
import PipelineKit

@Observable
final class ContactsListViewModel {
    var searchText: String = ""

    func filterContacts(_ contacts: [Contact]) -> [Contact] {
        var filtered = contacts

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            filtered = filtered.filter { contact in
                contact.fullName.lowercased().contains(query) ||
                (contact.companyName?.lowercased().contains(query) ?? false) ||
                (contact.email?.lowercased().contains(query) ?? false)
            }
        }

        return filtered.sorted { lhs, rhs in
            let lhsName = lhs.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhsName = rhs.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if lhsName.caseInsensitiveCompare(rhsName) == .orderedSame {
                return lhs.updatedAt > rhs.updatedAt
            }
            return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
        }
    }
}
