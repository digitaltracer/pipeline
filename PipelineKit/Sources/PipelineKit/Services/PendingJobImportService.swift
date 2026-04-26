import Foundation

public struct PendingJobImport: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var capturedPage: JobCapturedPage
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        capturedPage: JobCapturedPage,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.capturedPage = capturedPage
        self.createdAt = createdAt
    }
}

public enum PendingJobImportService {
    private static let importsKey = "PendingJobImportService.imports"
    public static let reviewURLString = "pipeline://job-imports/review"

    public static func enqueue(_ capturedPage: JobCapturedPage) throws -> PendingJobImport {
        let importItem = PendingJobImport(capturedPage: capturedPage)
        var imports = loadAll()
        imports.removeAll { $0.capturedPage.url == capturedPage.url }
        imports.insert(importItem, at: 0)
        try save(imports)
        return importItem
    }

    public static func loadLatest() -> PendingJobImport? {
        loadAll().sorted { $0.createdAt > $1.createdAt }.first
    }

    public static func remove(id: UUID) {
        var imports = loadAll()
        imports.removeAll { $0.id == id }
        try? save(imports)
    }

    public static func loadAll() -> [PendingJobImport] {
        guard let defaults = UserDefaults(suiteName: SharedContainer.appGroupID),
              let data = defaults.data(forKey: importsKey) else {
            return []
        }

        return (try? JSONDecoder().decode([PendingJobImport].self, from: data)) ?? []
    }

    private static func save(_ imports: [PendingJobImport]) throws {
        guard let defaults = UserDefaults(suiteName: SharedContainer.appGroupID) else {
            throw AIServiceError.apiError("Pipeline shared storage is unavailable.")
        }

        let trimmed = Array(imports.prefix(20))
        let data = try JSONEncoder().encode(trimmed)
        defaults.set(data, forKey: importsKey)
    }
}

public extension Notification.Name {
    static let pipelinePendingJobImportDidChange = Notification.Name("pipelinePendingJobImportDidChange")
}
