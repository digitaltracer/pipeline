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
                    UserDefaults.standard.set(
                        Self.cloudSyncStartupErrorMessage(for: error),
                        forKey: Constants.UserDefaultsKeys.cloudSyncStartupError
                    )
                    print("CloudKit initialization failed; using local storage only: \(error)")
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
        let nsError = error as NSError
        let recoverySuggestion = nsError.localizedRecoverySuggestion?.trimmingCharacters(in: .whitespacesAndNewlines)
        let failureReason = nsError.localizedFailureReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        let details: [String] = [failureReason, description, recoverySuggestion].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        guard !details.isEmpty else {
            return "CloudKit could not start for this launch."
        }

        return details.joined(separator: "\n")
    }
}
