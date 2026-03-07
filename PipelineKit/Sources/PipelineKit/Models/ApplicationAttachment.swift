import Foundation
import SwiftData

@Model
public final class ApplicationAttachment {
    public var id: UUID = UUID()
    private var kindRawValue: String = ApplicationAttachmentKind.file.rawValue
    private var categoryRawValue: String = ApplicationAttachmentCategory.other.rawValue
    public var title: String = ""
    public var tags: [String] = []
    public var managedStoragePath: String?
    public var originalFilename: String?
    public var contentType: String?
    public var fileSize: Int64?
    public var externalURL: String?
    public var noteBody: String?
    public var attachmentDescription: String?
    public var isSubmittedResume: Bool = false
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()

    public var application: JobApplication?

    public var kind: ApplicationAttachmentKind {
        get { ApplicationAttachmentKind(rawValue: kindRawValue) ?? .file }
        set { kindRawValue = newValue.rawValue }
    }

    public var category: ApplicationAttachmentCategory {
        get { ApplicationAttachmentCategory(rawValue: categoryRawValue) ?? .other }
        set { categoryRawValue = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        title: String,
        kind: ApplicationAttachmentKind,
        category: ApplicationAttachmentCategory,
        tags: [String] = [],
        managedStoragePath: String? = nil,
        originalFilename: String? = nil,
        contentType: String? = nil,
        fileSize: Int64? = nil,
        externalURL: String? = nil,
        noteBody: String? = nil,
        attachmentDescription: String? = nil,
        isSubmittedResume: Bool = false,
        application: JobApplication? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kindRawValue = kind.rawValue
        self.categoryRawValue = category.rawValue
        self.title = title
        self.tags = ApplicationAttachment.normalizedTags(tags)
        self.managedStoragePath = managedStoragePath
        self.originalFilename = originalFilename
        self.contentType = contentType
        self.fileSize = fileSize
        self.externalURL = externalURL
        self.noteBody = noteBody
        self.attachmentDescription = attachmentDescription
        self.isSubmittedResume = isSubmittedResume
        self.application = application
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var resolvedTitle: String {
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }

        if let originalFilename,
           !originalFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return originalFilename
        }

        if let externalURL,
           !externalURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return externalURL
        }

        return kind.displayName
    }

    public var normalizedExternalURL: URL? {
        guard let externalURL else { return nil }
        return URL(string: URLHelpers.normalize(externalURL))
    }

    public var isFile: Bool { kind == .file }
    public var isLink: Bool { kind == .link }
    public var isNote: Bool { kind == .note }

    public func setTags(_ value: [String]) {
        tags = Self.normalizedTags(value)
        updateTimestamp()
    }

    public func markSubmittedResume(_ value: Bool) {
        isSubmittedResume = value
        updateTimestamp()
    }

    public func updateTimestamp() {
        updatedAt = Date()
    }

    public static func normalizedTags(_ value: [String]) -> [String] {
        var seen = Set<String>()
        return value
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter {
                let key = $0.lowercased()
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }
}
