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

public struct LinkedInCSVImportProgress: Sendable, Hashable {
    public let processed: Int
    public let total: Int

    public init(processed: Int, total: Int) {
        self.processed = processed
        self.total = total
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return min(1.0, Double(processed) / Double(total))
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

public final class LinkedInCSVImportService: @unchecked Sendable {
    public static let shared = LinkedInCSVImportService()

    private static let persistBatchSize = 200

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

    private static let dateFormatters: [DateFormatter] = {
        ["MM/dd/yyyy", "yyyy-MM-dd", "dd MMM yyyy", "MMM d, yyyy"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
    }()

    private init() {}

    // MARK: - Async API (preferred)

    public func importFile(
        at url: URL,
        container: ModelContainer,
        progress: (@Sendable (LinkedInCSVImportProgress) -> Void)? = nil
    ) async throws -> LinkedInCSVImportResult {
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

        return try await importCSVString(
            csv,
            sourceFileName: url.lastPathComponent,
            container: container,
            progress: progress
        )
    }

    public func importCSVString(
        _ csv: String,
        sourceFileName: String,
        container: ModelContainer,
        progress: (@Sendable (LinkedInCSVImportProgress) -> Void)? = nil
    ) async throws -> LinkedInCSVImportResult {
        let prepared = try preparePersistenceInput(csv: csv)
        try Task.checkCancellation()
        progress?(LinkedInCSVImportProgress(processed: 0, total: prepared.candidates.count))

        let context = ModelContext(container)
        context.autosaveEnabled = false

        return try await persist(
            candidates: prepared.candidates,
            skippedCount: prepared.skippedCount,
            sourceFileName: sourceFileName,
            context: context,
            progress: progress,
            yieldBetweenBatches: true
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

    // MARK: - Sync API (preserved for tests and legacy callers)

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
        let prepared = try preparePersistenceInput(csv: csv)
        return try persistSynchronously(
            candidates: prepared.candidates,
            skippedCount: prepared.skippedCount,
            sourceFileName: sourceFileName,
            context: context
        )
    }

    // MARK: - Parse + candidate construction (pure)

    private struct PreparedInput {
        let candidates: [ImportedConnectionCandidate]
        let skippedCount: Int
    }

    private func preparePersistenceInput(csv: String) throws -> PreparedInput {
        let sanitized = strippingLinkedInPreamble(from: csv)
        let rows = CSVParser.parse(sanitized)
        guard let headerRow = rows.first, !headerRow.isEmpty else {
            throw LinkedInCSVImportError.invalidFormat("The LinkedIn CSV is empty.")
        }

        let headerMap = try resolveHeaders(headerRow)

        var candidates: [ImportedConnectionCandidate] = []
        candidates.reserveCapacity(rows.count)
        var skippedCount = 0

        for rawRow in rows.dropFirst() {
            if rawRow.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
                continue
            }
            if let candidate = makeCandidate(from: rawRow, headers: headerMap) {
                candidates.append(candidate)
            } else {
                skippedCount += 1
            }
        }

        return PreparedInput(candidates: candidates, skippedCount: skippedCount)
    }

    /// LinkedIn's official `Connections.csv` export begins with a "Notes:" block and a
    /// multi-line quoted disclaimer paragraph before the real header row. Strip anything
    /// before the first line that looks like the LinkedIn header so the parser sees a
    /// well-formed CSV.
    private func strippingLinkedInPreamble(from csv: String) -> String {
        let lines = csv.components(separatedBy: "\n")
        guard let headerLineIndex = lines.firstIndex(where: isLinkedInHeaderLine),
              headerLineIndex > 0 else {
            return csv
        }
        return lines[headerLineIndex...].joined(separator: "\n")
    }

    private func isLinkedInHeaderLine(_ line: String) -> Bool {
        let cells = line
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let firstNameAliases = (requiredHeaderGroups[.firstName] ?? []).map { $0.lowercased() }
        let lastNameAliases = (requiredHeaderGroups[.lastName] ?? []).map { $0.lowercased() }
        let hasFirstName = firstNameAliases.contains { cells.contains($0) }
        let hasLastName = lastNameAliases.contains { cells.contains($0) }
        return hasFirstName && hasLastName
    }

    // MARK: - Persistence (shared logic)

    private func persist(
        candidates: [ImportedConnectionCandidate],
        skippedCount: Int,
        sourceFileName: String,
        context: ModelContext,
        progress: (@Sendable (LinkedInCSVImportProgress) -> Void)?,
        yieldBetweenBatches: Bool
    ) async throws -> LinkedInCSVImportResult {
        let total = candidates.count

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

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()

            applyCandidate(
                candidate,
                batch: batch,
                context: context,
                connectionsByURL: &connectionsByURL,
                connectionsByLookupKey: &connectionsByLookupKey,
                importedCount: &importedCount,
                updatedCount: &updatedCount
            )

            let processed = index + 1
            let isFinal = processed == total
            if processed % Self.persistBatchSize == 0 || isFinal {
                try context.save()
                progress?(LinkedInCSVImportProgress(processed: processed, total: total))
                if yieldBetweenBatches && !isFinal {
                    await Task.yield()
                    try Task.checkCancellation()
                }
            }
        }

        batch.importedCount = importedCount
        batch.updatedCount = updatedCount
        batch.skippedCount = skippedCount
        batch.errorCount = 0
        batch.notes = nil
        batch.updateTimestamp()

        try context.save()

        return LinkedInCSVImportResult(
            batchID: batch.id,
            importedCount: importedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
            errorCount: 0,
            notes: nil
        )
    }

    private func persistSynchronously(
        candidates: [ImportedConnectionCandidate],
        skippedCount: Int,
        sourceFileName: String,
        context: ModelContext
    ) throws -> LinkedInCSVImportResult {
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

        for candidate in candidates {
            applyCandidate(
                candidate,
                batch: batch,
                context: context,
                connectionsByURL: &connectionsByURL,
                connectionsByLookupKey: &connectionsByLookupKey,
                importedCount: &importedCount,
                updatedCount: &updatedCount
            )
        }

        batch.importedCount = importedCount
        batch.updatedCount = updatedCount
        batch.skippedCount = skippedCount
        batch.errorCount = 0
        batch.notes = nil
        batch.updateTimestamp()

        try context.save()

        return LinkedInCSVImportResult(
            batchID: batch.id,
            importedCount: importedCount,
            updatedCount: updatedCount,
            skippedCount: skippedCount,
            errorCount: 0,
            notes: nil
        )
    }

    private func applyCandidate(
        _ candidate: ImportedConnectionCandidate,
        batch: NetworkImportBatch,
        context: ModelContext,
        connectionsByURL: inout [String: ImportedNetworkConnection],
        connectionsByLookupKey: inout [String: ImportedNetworkConnection],
        importedCount: inout Int,
        updatedCount: inout Int
    ) {
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

    // MARK: - Helpers

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
        for formatter in Self.dateFormatters {
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
