import Foundation
import SwiftData
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public enum ApplicationAttachmentStorageError: LocalizedError {
    case invalidSourceURL
    case failedToResolveStorageRoot
    case missingManagedFilePath
    case unsupportedAttachmentKind

    public var errorDescription: String? {
        switch self {
        case .invalidSourceURL:
            return "The selected file could not be accessed."
        case .failedToResolveStorageRoot:
            return "Pipeline could not resolve attachment storage."
        case .missingManagedFilePath:
            return "The attachment file path is missing."
        case .unsupportedAttachmentKind:
            return "This attachment type cannot be stored as a managed file."
        }
    }
}

public struct ApplicationAttachmentStorageService {
    public typealias RootURLProvider = () -> URL?

    private let fileManager: FileManager
    private let storageRootProvider: RootURLProvider

    public init(
        fileManager: FileManager = .default,
        storageRootProvider: @escaping RootURLProvider = ApplicationAttachmentStorageService.defaultStorageRootURL
    ) {
        self.fileManager = fileManager
        self.storageRootProvider = storageRootProvider
    }

    public func createFileAttachment(
        from sourceURL: URL,
        title: String? = nil,
        category: ApplicationAttachmentCategory = .other,
        tags: [String] = [],
        isSubmittedResume: Bool = false,
        for application: JobApplication,
        in context: ModelContext
    ) throws -> ApplicationAttachment {
        guard sourceURL.isFileURL else {
            throw ApplicationAttachmentStorageError.invalidSourceURL
        }

        let filename = sourceURL.lastPathComponent
        let data = try Data(contentsOf: sourceURL)
        let contentType = resolvedContentType(for: sourceURL)
        return try createManagedFileAttachment(
            data: data,
            preferredFilename: filename,
            title: title,
            contentType: contentType,
            category: category,
            tags: tags,
            isSubmittedResume: isSubmittedResume,
            for: application,
            in: context
        )
    }

    public func createManagedFileAttachment(
        data: Data,
        preferredFilename: String,
        title: String? = nil,
        contentType: String? = nil,
        category: ApplicationAttachmentCategory = .other,
        tags: [String] = [],
        isSubmittedResume: Bool = false,
        for application: JobApplication,
        in context: ModelContext
    ) throws -> ApplicationAttachment {
        let attachment = ApplicationAttachment(
            title: resolvedTitle(title, fallbackFilename: preferredFilename),
            kind: .file,
            category: category,
            tags: tags,
            originalFilename: preferredFilename,
            contentType: contentType,
            fileSize: Int64(data.count),
            isSubmittedResume: isSubmittedResume,
            application: application
        )

        let relativePath = makeManagedRelativePath(
            for: attachment,
            applicationID: application.id,
            preferredFilename: preferredFilename
        )
        let destinationURL = try absoluteURL(forRelativeManagedPath: relativePath)
        let directoryURL = destinationURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: destinationURL, options: .atomic)

        attachment.managedStoragePath = relativePath
        attachment.fileSize = Int64(data.count)

        try persist(
            attachment,
            for: application,
            markSubmittedResume: isSubmittedResume,
            in: context
        )
        return attachment
    }

    public func createLinkAttachment(
        title: String,
        urlString: String,
        category: ApplicationAttachmentCategory = .link,
        tags: [String] = [],
        description: String? = nil,
        for application: JobApplication,
        in context: ModelContext
    ) throws -> ApplicationAttachment {
        let attachment = ApplicationAttachment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .link,
            category: category,
            tags: tags,
            externalURL: URLHelpers.normalize(urlString),
            attachmentDescription: description,
            application: application
        )
        try persist(attachment, for: application, markSubmittedResume: false, in: context)
        return attachment
    }

    public func createNoteAttachment(
        title: String,
        body: String,
        category: ApplicationAttachmentCategory = .note,
        tags: [String] = [],
        description: String? = nil,
        for application: JobApplication,
        in context: ModelContext
    ) throws -> ApplicationAttachment {
        let attachment = ApplicationAttachment(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: .note,
            category: category,
            tags: tags,
            noteBody: body,
            attachmentDescription: description,
            application: application
        )
        try persist(attachment, for: application, markSubmittedResume: false, in: context)
        return attachment
    }

    public func updateMetadata(
        for attachment: ApplicationAttachment,
        title: String,
        category: ApplicationAttachmentCategory,
        tags: [String],
        description: String?,
        urlString: String?,
        noteBody: String?,
        isSubmittedResume: Bool,
        in application: JobApplication,
        context: ModelContext
    ) throws {
        attachment.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        attachment.category = category
        attachment.setTags(tags)
        attachment.attachmentDescription = description

        switch attachment.kind {
        case .file:
            attachment.markSubmittedResume(isSubmittedResume)
        case .link:
            attachment.externalURL = urlString.map(URLHelpers.normalize)
            attachment.markSubmittedResume(false)
        case .note:
            attachment.noteBody = noteBody
            attachment.markSubmittedResume(false)
        }

        if isSubmittedResume {
            try ensureSingleSubmittedResume(current: attachment, in: application, context: context)
        }

        application.updateTimestamp()
        try context.save()
    }

    public func deleteAttachment(
        _ attachment: ApplicationAttachment,
        from application: JobApplication,
        in context: ModelContext
    ) throws {
        if let managedStoragePath = attachment.managedStoragePath {
            let fileURL = try absoluteURL(forRelativeManagedPath: managedStoragePath)
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
        }

        application.attachments?.removeAll(where: { $0.id == attachment.id })
        application.updateTimestamp()
        context.delete(attachment)
        try context.save()
    }

    public func managedFileURL(for attachment: ApplicationAttachment) throws -> URL {
        guard attachment.kind == .file else {
            throw ApplicationAttachmentStorageError.unsupportedAttachmentKind
        }
        guard let managedStoragePath = attachment.managedStoragePath else {
            throw ApplicationAttachmentStorageError.missingManagedFilePath
        }
        return try absoluteURL(forRelativeManagedPath: managedStoragePath)
    }

    public func ensureSingleSubmittedResume(
        current attachment: ApplicationAttachment,
        in application: JobApplication,
        context: ModelContext
    ) throws {
        for existing in application.attachments ?? [] where existing.id != attachment.id {
            if existing.isSubmittedResume {
                existing.markSubmittedResume(false)
            }
        }

        attachment.markSubmittedResume(true)
        attachment.category = .resume
        application.updateTimestamp()
        try context.save()
    }

    public func makeManagedRelativePath(
        for attachment: ApplicationAttachment,
        applicationID: UUID,
        preferredFilename: String
    ) -> String {
        let sanitized = sanitizedFilename(preferredFilename)
        return [
            Constants.iCloud.attachmentsDirectoryName,
            applicationID.uuidString,
            Constants.iCloud.attachmentsSubdirectoryName,
            "\(attachment.id.uuidString)-\(sanitized)"
        ].joined(separator: "/")
    }

    public func absoluteURL(forRelativeManagedPath relativePath: String) throws -> URL {
        guard let rootURL = storageRootProvider() else {
            throw ApplicationAttachmentStorageError.failedToResolveStorageRoot
        }
        return rootURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    public static func defaultStorageRootURL() -> URL? {
        let fileManager = FileManager.default

        if let ubiquitousRoot = fileManager.url(
            forUbiquityContainerIdentifier: Constants.iCloud.containerID
        ) {
            let documentsRoot = ubiquitousRoot.appendingPathComponent("Documents", isDirectory: true)
            try? fileManager.createDirectory(at: documentsRoot, withIntermediateDirectories: true)
            return documentsRoot
        }

        return SharedContainer.appGroupStoreURL()?
            .deletingLastPathComponent()
            .appendingPathComponent(Constants.iCloud.localFallbackDocumentsDirectoryName, isDirectory: true)
    }

    private func persist(
        _ attachment: ApplicationAttachment,
        for application: JobApplication,
        markSubmittedResume: Bool,
        in context: ModelContext
    ) throws {
        if application.attachments == nil {
            application.attachments = []
        }

        application.attachments?.append(attachment)
        application.updateTimestamp()
        context.insert(attachment)

        if markSubmittedResume {
            try ensureSingleSubmittedResume(current: attachment, in: application, context: context)
        } else {
            try context.save()
        }
    }

    private func resolvedTitle(_ title: String?, fallbackFilename: String) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallbackFilename : trimmed
    }

    private func sanitizedFilename(_ filename: String) -> String {
        let trimmed = filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "attachment" }

        let ext = URL(fileURLWithPath: trimmed).pathExtension
        let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitizedBase = baseName.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(sanitizedBase)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let finalBase = collapsed.isEmpty ? "attachment" : collapsed

        guard !ext.isEmpty else { return finalBase }
        return "\(finalBase).\(ext.lowercased())"
    }

    private func resolvedContentType(for sourceURL: URL) -> String? {
        #if canImport(UniformTypeIdentifiers)
        if let type = try? sourceURL.resourceValues(forKeys: [.contentTypeKey]).contentType {
            return type.identifier
        }

        if let type = UTType(filenameExtension: sourceURL.pathExtension) {
            return type.identifier
        }
        #endif

        return nil
    }
}
