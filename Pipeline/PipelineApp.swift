import SwiftUI
import SwiftData
import PipelineKit

// MARK: - Development Flag
// Set to false to hide/disable CloudKit sync controls and force local-only storage.
// Useful when signing does not include iCloud capabilities.
private let cloudSyncSupportedInThisBuild = true

@main
struct PipelineApp: App {
    let modelContainer: ModelContainer
    @State private var settingsViewModel: SettingsViewModel
    @State private var appLockCoordinator: AppLockCoordinator
    @State private var onboardingStore = OnboardingStore()

    init() {
        // Migrate legacy store to App Group container before opening
        SharedContainer.migrateStoreIfNeeded()

        // Pull any iCloud-synced preferences into UserDefaults BEFORE any
        // view model reads them, and seed the cloud store with already-set
        // local values on first launch after upgrade.
        SettingsSyncCoordinator.shared.start()

        do {
            let storedSyncPreference = UserDefaults.standard.object(
                forKey: Constants.UserDefaultsKeys.cloudSyncEnabled
            ) as? Bool

            let preferredSyncEnabled = cloudSyncSupportedInThisBuild && (storedSyncPreference ?? true)

            let container: ModelContainer
            let syncEnabledAtLaunch: Bool

            if preferredSyncEnabled {
                do {
                    container = try SharedContainer.makeModelContainer(
                        cloudKitDatabase: .private(Constants.iCloud.containerID)
                    )
                    syncEnabledAtLaunch = true
                    UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.cloudSyncStartupError)
                } catch {
                    // If CloudKit setup is invalid for the current signing profile, keep the app usable.
                    container = try SharedContainer.makeModelContainer(
                        cloudKitDatabase: .none
                    )
                    syncEnabledAtLaunch = false
                    let detailedMessage = Self.cloudSyncStartupErrorMessage(for: error)
                    UserDefaults.standard.set(
                        detailedMessage,
                        forKey: Constants.UserDefaultsKeys.cloudSyncStartupError
                    )
                    print("CloudKit initialization failed; using local storage only.\n\(detailedMessage)")
                }
            } else {
                container = try SharedContainer.makeModelContainer(
                    cloudKitDatabase: .none
                )
                syncEnabledAtLaunch = false
                UserDefaults.standard.removeObject(forKey: Constants.UserDefaultsKeys.cloudSyncStartupError)
            }

            self.modelContainer = container

            let migrationContext = ModelContext(container)
            _ = try? ApplicationTimelineMigrationService.migrateLegacyInterviewLogs(in: migrationContext)
            _ = try? JobSearchCycleMigrationService.backfillImportedCycleIfNeeded(in: migrationContext)
            _ = try? CompanyLinkingService.backfillApplicationsIfNeeded(in: migrationContext)

            let settingsViewModel = SettingsViewModel(
                cloudSyncSupported: cloudSyncSupportedInThisBuild,
                cloudSyncEnabledAtLaunch: syncEnabledAtLaunch
            )
            _settingsViewModel = State(initialValue: settingsViewModel)
            _appLockCoordinator = State(initialValue: AppLockCoordinator(settingsViewModel: settingsViewModel))

            NotificationService.shared.registerCategories()
            #if os(macOS)
            CursorCoordinator.shared.start()
            #endif
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppLockRootView {
                ContentView(
                    settingsViewModel: settingsViewModel,
                    onboardingStore: onboardingStore
                )
            }
            .environment(appLockCoordinator)
            .onOpenURL { url in
                if !GoogleCalendarConfiguration.handleSignInURL(url) {
                    Task { @MainActor in
                        NotificationService.shared.handleDeepLinkURL(url)
                    }
                }
            }
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1500, height: 860)
        #endif

        #if os(macOS)
        Settings {
            AppLockRootView {
                SettingsView(
                    viewModel: settingsViewModel,
                    entryPoint: .root,
                    onReplayOnboarding: {
                        onboardingStore.presentIntro(force: true)
                    },
                    onboardingGuidanceMuted: Binding(
                        get: { onboardingStore.guidanceMuted },
                        set: { onboardingStore.guidanceMuted = $0 }
                    )
                )
                .modelContainer(modelContainer)
            }
            .environment(appLockCoordinator)
        }
        #endif
    }

    private static func cloudSyncStartupErrorMessage(for error: Error) -> String {
        let lines = collectErrorLines(from: error as NSError, depth: 0)
        let deduped = Array(NSOrderedSet(array: lines)) as? [String] ?? lines
        let joined = deduped.joined(separator: "\n")
        return joined.isEmpty ? "CloudKit could not start for this launch." : joined
    }

    private static func collectErrorLines(from nsError: NSError, depth: Int) -> [String] {
        let indent = String(repeating: "  ", count: depth)
        var lines: [String] = []

        lines.append("\(indent)[\(nsError.domain) \(nsError.code)] \(nsError.localizedDescription)")
        if let reason = nsError.localizedFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines),
           !reason.isEmpty {
            lines.append("\(indent)Reason: \(reason)")
        }
        if let suggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !suggestion.isEmpty {
            lines.append("\(indent)Suggestion: \(suggestion)")
        }

        let skippedUserInfoKeys: Set<String> = [
            NSLocalizedDescriptionKey,
            NSLocalizedFailureReasonErrorKey,
            NSLocalizedRecoverySuggestionErrorKey,
            NSUnderlyingErrorKey,
            "NSMultipleUnderlyingErrorsKey"
        ]
        for (key, value) in nsError.userInfo where !skippedUserInfoKeys.contains(key) {
            lines.append("\(indent)\(key): \(value)")
        }

        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            lines.append(contentsOf: collectErrorLines(from: underlying, depth: depth + 1))
        }
        if let siblings = nsError.userInfo["NSMultipleUnderlyingErrorsKey"] as? [NSError] {
            for sibling in siblings {
                lines.append(contentsOf: collectErrorLines(from: sibling, depth: depth + 1))
            }
        }

        return lines
    }
}
