import Foundation
import SwiftData

public enum SharedContainer {
    public static let appGroupID = "group.io.github.digitaltracer.pipeline"

    /// Key used to track whether store migration has been completed.
    private static let migrationCompletedKey = "SharedContainer.migrationCompleted"

    public static func makeModelContainer(
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase = .none
    ) throws -> ModelContainer {
        let schema = Schema([
            JobApplication.self,
            InterviewLog.self
        ])

        let storeURL = appGroupStoreURL() ?? defaultStoreURL()

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: cloudKitDatabase
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }

    // MARK: - Store Migration

    /// Migrates data from the legacy default SwiftData store to the App Group
    /// container if needed. Call once at app launch before creating the
    /// `ModelContainer`.
    ///
    /// SwiftData stores consist of multiple files sharing a base name
    /// (`.store`, `.store-shm`, `.store-wal`). This method copies all of
    /// them atomically.
    public static func migrateStoreIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationCompletedKey) else { return }

        guard let groupURL = appGroupStoreURL() else {
            // No App Group available (e.g., simulator) — skip migration
            return
        }

        let legacyURL = legacyStoreURL()

        // Only migrate if the legacy store exists AND the group store does not
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyURL.path) else {
            // No legacy store — mark as migrated so we don't check again
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            return
        }

        guard !fm.fileExists(atPath: groupURL.path) else {
            // Group store already exists — don't overwrite
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            return
        }

        // Ensure target directory exists
        let groupDir = groupURL.deletingLastPathComponent()
        try? fm.createDirectory(at: groupDir, withIntermediateDirectories: true)

        // Copy all associated store files (.store, .store-shm, .store-wal)
        let baseName = legacyURL.lastPathComponent
        let legacyDir = legacyURL.deletingLastPathComponent()
        let suffixes = ["", "-shm", "-wal"]

        var allCopied = true
        for suffix in suffixes {
            let srcFile = legacyDir.appendingPathComponent(baseName + suffix)
            let dstFile = groupDir.appendingPathComponent(groupURL.lastPathComponent + suffix)

            guard fm.fileExists(atPath: srcFile.path) else { continue }
            do {
                try fm.copyItem(at: srcFile, to: dstFile)
            } catch {
                print("SharedContainer: failed to copy \(srcFile.lastPathComponent): \(error)")
                allCopied = false
            }
        }

        if allCopied {
            UserDefaults.standard.set(true, forKey: migrationCompletedKey)
            print("SharedContainer: migrated store from \(legacyDir.path) to \(groupDir.path)")
        }
    }

    // MARK: - URLs

    public static func appGroupStoreURL() -> URL? {
        guard let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else {
            return nil
        }
        return containerURL.appendingPathComponent("Pipeline.store")
    }

    /// The location SwiftData used before App Groups were configured.
    /// On macOS this is ~/Library/Application Support/default.store by default
    /// when no explicit URL is given to ModelConfiguration.
    private static func legacyStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("default.store")
    }

    private static func defaultStoreURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let pipelineDir = appSupport.appendingPathComponent("Pipeline")
        try? FileManager.default.createDirectory(at: pipelineDir, withIntermediateDirectories: true)
        return pipelineDir.appendingPathComponent("Pipeline.store")
    }
}
