import Foundation
import SwiftData

public struct NetworkReferralSuggestion: Identifiable, Equatable, Sendable {
    public let connectionID: UUID
    public let contactID: UUID?
    public let displayName: String
    public let companyName: String
    public let title: String?
    public let email: String?
    public let linkedInURL: String?
    public let matchedViaAlias: Bool
    public let reason: String
    public let isPromoted: Bool

    public var id: UUID { connectionID }

    public init(
        connectionID: UUID,
        contactID: UUID?,
        displayName: String,
        companyName: String,
        title: String?,
        email: String?,
        linkedInURL: String?,
        matchedViaAlias: Bool,
        reason: String,
        isPromoted: Bool
    ) {
        self.connectionID = connectionID
        self.contactID = contactID
        self.displayName = displayName
        self.companyName = companyName
        self.title = title
        self.email = email
        self.linkedInURL = linkedInURL
        self.matchedViaAlias = matchedViaAlias
        self.reason = reason
        self.isPromoted = isPromoted
    }
}

public struct PotentialCompanyAliasSuggestion: Identifiable, Equatable, Hashable, Sendable {
    public let canonicalName: String
    public let aliasName: String
    public let reason: String

    public var id: String { "\(canonicalName.lowercased())|\(aliasName.lowercased())" }
}

@MainActor
public enum NetworkReferralMatchingService {
    public static func suggestions(
        for application: JobApplication,
        in context: ModelContext
    ) throws -> [NetworkReferralSuggestion] {
        try suggestions(
            for: application,
            connections: context.fetch(FetchDescriptor<ImportedNetworkConnection>()).filter { $0.status != .ignored },
            aliases: context.fetch(FetchDescriptor<CompanyAlias>())
        )
    }

    public static func suggestions(
        for application: JobApplication,
        connections: [ImportedNetworkConnection],
        aliases: [CompanyAlias]
    ) throws -> [NetworkReferralSuggestion] {
        let targetKey = CompanyProfile.normalizedName(from: application.companyName)
        guard !targetKey.isEmpty else { return [] }

        let companyKeys = relatedCompanyKeys(for: targetKey, aliases: aliases)

        return connections.compactMap { connection in
            guard connection.status != .ignored else { return nil }
            guard !connection.normalizedCompanyName.isEmpty else { return nil }
            guard companyKeys.contains(connection.normalizedCompanyName) else { return nil }

            let matchedViaAlias = connection.normalizedCompanyName != targetKey
            let reason = matchedViaAlias
                ? "Matched through a confirmed company alias."
                : "Works at the same company as this application."

            return NetworkReferralSuggestion(
                connectionID: connection.id,
                contactID: connection.linkedContact?.id,
                displayName: connection.fullName,
                companyName: connection.displayCompanyName,
                title: connection.title,
                email: connection.linkedContact?.email ?? connection.email,
                linkedInURL: connection.linkedInURL ?? connection.linkedContact?.linkedInURL,
                matchedViaAlias: matchedViaAlias,
                reason: reason,
                isPromoted: connection.linkedContact != nil
            )
        }
        .sorted { lhs, rhs in
            if lhs.isPromoted != rhs.isPromoted {
                return lhs.isPromoted && !rhs.isPromoted
            }
            if (lhs.email != nil) != (rhs.email != nil) {
                return lhs.email != nil
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    public static func potentialAliasSuggestions(
        applications: [JobApplication],
        connections: [ImportedNetworkConnection],
        aliases: [CompanyAlias]
    ) -> [PotentialCompanyAliasSuggestion] {
        let knownPairs = Set(aliases.map { "\($0.normalizedCanonicalName)|\($0.normalizedAliasName)" })
        var suggestions: [PotentialCompanyAliasSuggestion] = []

        for application in applications {
            let appKey = CompanyProfile.normalizedName(from: application.companyName)
            guard !appKey.isEmpty else { continue }

            for connection in connections {
                let companyKey = connection.normalizedCompanyName
                guard !companyKey.isEmpty, companyKey != appKey else { continue }
                guard !knownPairs.contains("\(appKey)|\(companyKey)") else { continue }

                if looksLikeAlias(lhs: appKey, rhs: companyKey) {
                    suggestions.append(
                        PotentialCompanyAliasSuggestion(
                            canonicalName: application.companyName,
                            aliasName: connection.displayCompanyName,
                            reason: "These names share enough tokens that they may refer to the same company."
                        )
                    )
                }
            }
        }

        return suggestions.uniquedPreservingOrder()
    }

    @discardableResult
    public static func addAlias(
        canonicalName: String,
        aliasName: String,
        in context: ModelContext
    ) throws -> CompanyAlias {
        let normalizedCanonicalName = CompanyProfile.normalizedName(from: canonicalName)
        let normalizedAliasName = CompanyProfile.normalizedName(from: aliasName)

        if let existing = try context.fetch(FetchDescriptor<CompanyAlias>()).first(where: {
            $0.normalizedCanonicalName == normalizedCanonicalName && $0.normalizedAliasName == normalizedAliasName
        }) {
            return existing
        }

        let alias = CompanyAlias(canonicalName: canonicalName, aliasName: aliasName)
        context.insert(alias)
        try context.save()
        return alias
    }

    @discardableResult
    public static func promote(
        connection: ImportedNetworkConnection,
        relationship: String = "LinkedIn connection",
        in context: ModelContext
    ) throws -> Contact {
        let existingContacts = try context.fetch(FetchDescriptor<Contact>())

        let matchedContact = existingContacts.first(where: {
            if let linkedInURL = connection.linkedInURL,
               $0.linkedInURL?.lowercased() == linkedInURL.lowercased() {
                return true
            }

            return Contact.normalizedLookupKey(name: $0.fullName, companyName: $0.companyName) ==
                Contact.normalizedLookupKey(name: connection.fullName, companyName: connection.companyName)
        })

        let contact = matchedContact ?? Contact(
            fullName: connection.fullName,
            email: connection.email,
            companyName: connection.companyName,
            title: connection.title,
            relationship: relationship,
            linkedInURL: connection.linkedInURL
        )

        if matchedContact == nil {
            context.insert(contact)
        }

        if contact.email?.isEmpty ?? true {
            contact.email = connection.email
        }
        if contact.companyName?.isEmpty ?? true {
            contact.companyName = connection.companyName
        }
        if contact.title?.isEmpty ?? true {
            contact.title = connection.title
        }
        if contact.relationship?.isEmpty ?? true {
            contact.relationship = relationship
        }
        if contact.linkedInURL?.isEmpty ?? true {
            contact.linkedInURL = connection.linkedInURL
        }
        contact.updateTimestamp()

        connection.markPromoted(to: contact)
        try context.save()
        return contact
    }

    public static func setIgnored(
        _ ignored: Bool,
        for connection: ImportedNetworkConnection,
        in context: ModelContext
    ) throws {
        connection.status = ignored ? .ignored : (connection.linkedContact == nil ? .available : .promoted)
        connection.updateTimestamp()
        try context.save()
    }

    public static func connection(
        id: UUID,
        in context: ModelContext
    ) throws -> ImportedNetworkConnection? {
        try context.fetch(FetchDescriptor<ImportedNetworkConnection>()).first(where: { $0.id == id })
    }

    private static func relatedCompanyKeys(for target: String, aliases: [CompanyAlias]) -> Set<String> {
        var keys: Set<String> = [target]
        var changed = true

        while changed {
            changed = false

            for alias in aliases {
                if keys.contains(alias.normalizedCanonicalName) || keys.contains(alias.normalizedAliasName) {
                    let countBefore = keys.count
                    keys.insert(alias.normalizedCanonicalName)
                    keys.insert(alias.normalizedAliasName)
                    changed = changed || keys.count != countBefore
                }
            }
        }

        return keys
    }

    private static func looksLikeAlias(lhs: String, rhs: String) -> Bool {
        if lhs.contains(rhs) || rhs.contains(lhs) {
            return true
        }

        let lhsTokens = Set(lhs.split(separator: " ").map(String.init))
        let rhsTokens = Set(rhs.split(separator: " ").map(String.init))
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return false }
        return !lhsTokens.intersection(rhsTokens).isEmpty
    }
}
