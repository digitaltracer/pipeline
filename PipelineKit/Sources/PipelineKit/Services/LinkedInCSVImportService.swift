import Foundation
import SwiftData

public struct LinkedInCSVImportResult: Sendable {
    public let batchID: UUID
    public let importedCount: Int
    public let updatedCount: Int
    public let skippedCount: Int
    public let errorCount: Int
    public let notes: String?

    public init(
        batchID: UUID,
        importedCount: Int,
        updatedCount: Int,
        skippedCount: Int,
        errorCount: Int,
        notes: String?
    ) {
        self.batchID = batchID
        self.importedCount = importedCount
        self.updatedCount = updatedCount
        self.skippedCount = skippedCount
        self.errorCount = errorCount
        self.notes = notes
    }
}

public enum LinkedInCSVImportError: LocalizedError {
    case unreadableFile
    case invalidFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile:
            return "Pipeline could not read that CSV file."
        case .invalidFormat(let detail):
            return detail
        }
    }
}

@MainActor
public final class LinkedInCSVImportService {
    public static let shared = LinkedInCSVImportService()

    private let requiredHeaderGroups: [LinkedInHeaderKey: [String]] = [
        .firstName: ["First Name", "First name"],
        .lastName: ["Last Name", "Last name"]
    ]

    private let optionalHeaderGroups: [LinkedInHeaderKey: [String]] = [
        .email: ["Email Address", "Email", "E-mail Address"],
        .company: ["Company", "Current Company"],
        .position: ["Position", "Title", "Job Title"],
        .profileURL: ["URL", "Profile URL", "LinkedIn URL"],
        .connectedOn: ["Connected On", "Connected Date", "Connected On Date"]
    ]

    private lazy var dateFormatters: [DateFormatter] = {
        ["MM/dd/yyyy", "yyyy-MM-dd", "dd MMM yyyy", "MMM d, yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private init() {}

    public func importFile(at url: URL, into context: ModelContext) throws -> LinkedInCSVImportResult {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let csv = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .unicode) else {
            throw LinkedInCSVImportError.unreadableFile
        }

        return try importCSVString(
            csv,
            sourceFileName: url.lastPathComponent,
            into: context
        )
    }

    public func importCSVString(
        _ csv: String,
        sourceFileName: String,
        into context: ModelContext
    ) throws -> LinkedInCSVImportResult {
        let rows = CSVParser.parse(csv)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw LinkedInCSVImportError.invalidFormat("The LinkedIn CSV is empty.")
        }

        let headerMap = try resolveHeaders(headerRow)
        let batch = NetworkImportBatch(
            provider: .linkedInCSV,
            sourceFileName: sourceFileName,
            importedAt: Date()
        )
        context.insert(batch)

        let existingConnections = try context.fetch(FetchDescriptor<ImportedNetworkConnection>())
        var connectionsByURL = Dictionary(
            uniqueKeysWithValues: existingConnections.compactMap { connection in
                connection.linkedInURL.map { ($0.lowercased(), connection) }
            }
        )
        var connectionsByLookupKey = Dictionary(
            uniqueKeysWithValues: existingConnections.map { ($0.lookupKey, $0) }
        )

        var importedCount = 0
        var updatedCount = 0
        var skippedCount = 0
        let errorCount = 0
        let notes: [String] = []

        for rawRow in rows.dropFirst() {
            if rawRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }

            guard let candidate = makeCandidate(from: rawRow, headers: headerMap) else {
                skippedCount += 1
                continue
            }

            let identityURL = candidate.linkedInURL?.lowercased()
            let lookupKey = candidate.lookupKey
            let existing = identityURL.flatMap { connectionsByURL[$0] } ?? connectionsByLookupKey[lookupKey]

            if let existing {
                existing.fullName = candidate.fullName
                existing.email = candidate.email
                existing.companyName = candidate.companyName
                existing.title = candidate.title
                existing.linkedInURL = candidate.linkedInURL
                existing.connectedOn = candidate.connectedOn
                existing.notes = candidate.notes
                existing.providerRowID = candidate.providerRowID
                existing.batch = batch
                existing.refreshNormalizedFields()
                if existing.linkedContact != nil {
                    existing.status = .promoted
                }
                existing.updateTimestamp()
                updatedCount += 1
                if let identityURL {
                    connectionsByURL[identityURL] = existing
                }
                connectionsByLookupKey[existing.lookupKey] = existing
            } else {
                let connection = ImportedNetworkConnection(
                    provider: .linkedInCSV,
                    providerRowID: candidate.providerRowID,
                    fullName: candidate.fullName,
                    email: candidate.email,
                    companyName: candidate.companyName,
                    title: candidate.title,
                    linkedInURL: candidate.linkedInURL,
                    connectedOn: candidate.connectedOn,
                    notes: candidate.notes,
                    batch: batch
                )
                context.insert(connection)
                importedCount += 1
                if let identityURL {
                    connectionsByURL[identityURL] = connection
                }
                connectionsByLookupKey[connection.lookupKey] = connection
            }
        }

        batch.importedCount = importedCount
        batch.updatedCount = updatedCount
        batch.skippedCount = skippedCount
        batch.errorCount = errorCount
        batch.notes = notes.isEmpty ? nil : notes.uniquedPreservingOrder().joined(separator: "\n")
        batch.updateTimestamp()

        try context.save()

        return LinkedInCSVImportResult(
            batchID: batch.id,
            importedCount: importedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
            errorCount: errorCount,
            notes: batch.notes
        )
    }

    public func clearImportedConnections(in context: ModelContext) throws {
        for connection in try context.fetch(FetchDescriptor<ImportedNetworkConnection>()) {
            context.delete(connection)
        }

        for batch in try context.fetch(FetchDescriptor<NetworkImportBatch>()) {
            context.delete(batch)
        }

        try context.save()
    }

    private func resolveHeaders(_ headers: [String]) throws -> [LinkedInHeaderKey: Int] {
        let normalizedHeaders = headers.enumerated().reduce(into: [String: Int]()) { result, entry in
            result[entry.element.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()] = entry.offset
        }

        var resolved: [LinkedInHeaderKey: Int] = [:]

        for (key, candidates) in requiredHeaderGroups {
            guard let index = firstHeaderMatch(candidates, in: normalizedHeaders) else {
                throw LinkedInCSVImportError.invalidFormat(
                    "This CSV does not look like the official LinkedIn connections export. Missing \(candidates.first ?? key.rawValue)."
                )
            }
            resolved[key] = index
        }

        for (key, candidates) in optionalHeaderGroups {
            if let index = firstHeaderMatch(candidates, in: normalizedHeaders) {
                resolved[key] = index
            }
        }

        return resolved
    }

    private func firstHeaderMatch(_ candidates: [String], in headers: [String: Int]) -> Int? {
        for candidate in candidates {
            if let index = headers[candidate.lowercased()] {
                return index
            }
        }
        return nil
    }

    private func makeCandidate(
        from row: [String],
        headers: [LinkedInHeaderKey: Int]
    ) -> ImportedConnectionCandidate? {
        let firstName = value(.firstName, from: row, headers: headers)
        let lastName = value(.lastName, from: row, headers: headers)
        let fullName = [firstName, lastName]
            .compactMap { CompanyProfile.normalizedText($0) }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !fullName.isEmpty else {
            return nil
        }

        let companyName = CompanyProfile.normalizedText(value(.company, from: row, headers: headers))
        let linkedInURL = CompanyProfile.normalizedURLString(value(.profileURL, from: row, headers: headers))
        let connectedOn = parsedDate(value(.connectedOn, from: row, headers: headers))
        let providerRowID = linkedInURL ?? Contact.normalizedLookupKey(name: fullName, companyName: companyName) ?? UUID().uuidString

        return ImportedConnectionCandidate(
            providerRowID: providerRowID,
            fullName: fullName,
            email: CompanyProfile.normalizedText(value(.email, from: row, headers: headers)),
            companyName: companyName,
            title: CompanyProfile.normalizedText(value(.position, from: row, headers: headers)),
            linkedInURL: linkedInURL,
            connectedOn: connectedOn,
            notes: nil
        )
    }

    private func value(
        _ key: LinkedInHeaderKey,
        from row: [String],
        headers: [LinkedInHeaderKey: Int]
    ) -> String? {
        guard let index = headers[key], row.indices.contains(index) else { return nil }
        return row[index]
    }

    private func parsedDate(_ value: String?) -> Date? {
        guard let value = CompanyProfile.normalizedText(value) else { return nil }
        for formatter in dateFormatters {
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }
}

private enum LinkedInHeaderKey: String {
    case firstName
    case lastName
    case email
    case company
    case position
    case profileURL
    case connectedOn
}

private struct ImportedConnectionCandidate {
    let providerRowID: String
    let fullName: String
    let email: String?
    let companyName: String?
    let title: String?
    let linkedInURL: String?
    let connectedOn: Date?
    let notes: String?

    var lookupKey: String {
        Contact.normalizedLookupKey(name: fullName, companyName: companyName) ?? providerRowID
    }
}

private enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.makeIterator()

        while let character = iterator.next() {
            switch character {
            case "\"":
                if inQuotes, let next = iterator.next() {
                    if next == "\"" {
                        field.append("\"")
                    } else {
                        inQuotes = false
                        consume(next, field: &field, row: &row, rows: &rows, inQuotes: &inQuotes)
                    }
                } else {
                    inQuotes = false
                }
            default:
                consume(character, field: &field, row: &row, rows: &rows, inQuotes: &inQuotes)
            }

            if character == "\"" && !inQuotes && field.isEmpty && row.isEmpty {
                inQuotes = true
            }
        }

        row.append(field)
        if !row.isEmpty {
            rows.append(row)
        }

        return rows
    }

    private static func consume(
        _ character: Character,
        field: inout String,
        row: inout [String],
        rows: inout [[String]],
        inQuotes: inout Bool
    ) {
        if character == "\"" {
            inQuotes = true
            return
        }

        if character == "," && !inQuotes {
            row.append(field)
            field = ""
            return
        }

        if (character == "\n" || character == "\r") && !inQuotes {
            if character == "\r" {
                return
            }
            row.append(field)
            rows.append(row)
            row = []
            field = ""
            return
        }

        field.append(character)
    }
}
