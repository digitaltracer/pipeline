import Foundation

public extension Notification.Name {
    /// Posted on the main thread after `SettingsSyncCoordinator` applies a remote
    /// change from iCloud to `UserDefaults.standard`. `userInfo["changedKeys"]`
    /// carries the `[String]` of allowlisted keys that were updated.
    static let settingsDidChangeRemotely = Notification.Name("SettingsSyncCoordinator.settingsDidChangeRemotely")
}

/// Bridges allowlisted `UserDefaults.standard` keys to `NSUbiquitousKeyValueStore`
/// so simple preferences follow the user between devices, alongside the SwiftData
/// CloudKit sync that already covers `@Model` types. Secrets (Keychain) are never
/// touched.
///
/// Write-through: setters in `SettingsViewModel`, `OnboardingStore`,
/// `CustomValuesStore`, and theme helpers call `setSyncable(_:forKey:)` instead of
/// writing `UserDefaults` directly. The coordinator writes to both stores and
/// skips the KVS write when the value is already equal there.
///
/// Read-through: on `NSUbiquitousKeyValueStore.didChangeExternallyNotification`
/// the coordinator writes incoming values into `UserDefaults.standard` and posts
/// `.settingsDidChangeRemotely` so observers can rehydrate their in-memory state.
public final class SettingsSyncCoordinator: @unchecked Sendable {
    public static let shared = SettingsSyncCoordinator()

    private let allowlist = Constants.Sync.syncableUserDefaultsKeys
    private let defaults: UserDefaults
    private let kvStore: NSUbiquitousKeyValueStore
    private let lock = NSLock()
    private var isApplyingRemoteChange = false
    private var hasStarted = false

    private init(
        defaults: UserDefaults = .standard,
        kvStore: NSUbiquitousKeyValueStore = .default
    ) {
        self.defaults = defaults
        self.kvStore = kvStore
    }

    // MARK: - Lifecycle

    /// Call once at app launch, before any ViewModel reads `UserDefaults`. Pulls
    /// any cloud state into the local defaults (new-device onboarding) and
    /// seeds the cloud store with any already-set local values (migration for
    /// users upgrading into the sync-aware build).
    public func start() {
        lock.lock()
        guard !hasStarted else { lock.unlock(); return }
        hasStarted = true
        lock.unlock()

        kvStore.synchronize()
        performInitialSync()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleExternalChange(_:)),
            name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: kvStore
        )
    }

    // MARK: - Write-through

    /// Writes `value` to `UserDefaults.standard` and, if `key` is in the sync
    /// allowlist, mirrors it to iCloud KVS. Call this from `didSet` blocks on
    /// syncable settings. Unknown keys fall through to a plain defaults write.
    public func setSyncable(_ value: Any?, forKey key: String) {
        defaults.set(value, forKey: key)

        guard allowlist.contains(key) else { return }
        guard !isApplyingRemoteChange else { return }

        let existing = kvStore.object(forKey: key)
        if !valuesEqual(existing, value) {
            if let value {
                kvStore.set(value, forKey: key)
            } else {
                kvStore.removeObject(forKey: key)
            }
        }
    }

    /// Removes `key` from both stores. No-op on KVS if the key isn't in the
    /// allowlist.
    public func removeSyncable(forKey key: String) {
        defaults.removeObject(forKey: key)

        guard allowlist.contains(key) else { return }
        guard !isApplyingRemoteChange else { return }
        kvStore.removeObject(forKey: key)
    }

    // MARK: - Initial sync

    private func performInitialSync() {
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        for key in allowlist {
            let localValue = defaults.object(forKey: key)
            let cloudValue = kvStore.object(forKey: key)

            switch (localValue, cloudValue) {
            case (nil, let cloud?):
                defaults.set(cloud, forKey: key)
            case (let local?, nil):
                kvStore.set(local, forKey: key)
            default:
                break
            }
        }
    }

    // MARK: - Remote change

    @objc private func handleExternalChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }

        if let reason = userInfo[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int {
            let accepted: Set<Int> = [
                NSUbiquitousKeyValueStoreServerChange,
                NSUbiquitousKeyValueStoreInitialSyncChange,
                NSUbiquitousKeyValueStoreAccountChange
            ]
            guard accepted.contains(reason) else { return }
        }

        let changedKeys = (userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]) ?? []
        let relevantKeys = changedKeys.filter { allowlist.contains($0) }
        guard !relevantKeys.isEmpty else { return }

        DispatchQueue.main.async { [weak self] in
            self?.applyRemoteChanges(for: relevantKeys)
        }
    }

    private func applyRemoteChanges(for keys: [String]) {
        isApplyingRemoteChange = true
        defer { isApplyingRemoteChange = false }

        for key in keys {
            if let value = kvStore.object(forKey: key) {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        NotificationCenter.default.post(
            name: .settingsDidChangeRemotely,
            object: self,
            userInfo: ["changedKeys": keys]
        )
    }

    // MARK: - Helpers

    private func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let l?, let r?):
            return (l as? NSObject) == (r as? NSObject)
        }
    }
}
