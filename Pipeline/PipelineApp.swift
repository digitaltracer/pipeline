import SwiftUI
import SwiftData

// MARK: - Development Flag
// Set to false to hide/disable CloudKit sync controls and force local-only storage.
// Useful when signing does not include iCloud capabilities.
private let cloudSyncSupportedInThisBuild = true

@main
struct PipelineApp: App {
    let modelContainer: ModelContainer
    @State private var settingsViewModel: SettingsViewModel

    init() {
        do {
            let schema = Schema([
                JobApplication.self,
                InterviewLog.self
            ])

            let storedSyncPreference = UserDefaults.standard.object(
                forKey: Constants.UserDefaultsKeys.cloudSyncEnabled
            ) as? Bool

            let preferredSyncEnabled = cloudSyncSupportedInThisBuild && (storedSyncPreference ?? true)

            let container: ModelContainer
            let syncEnabledAtLaunch: Bool

            if preferredSyncEnabled {
                do {
                    container = try Self.makeModelContainer(
                        schema: schema,
                        cloudKitDatabase: .private(Constants.iCloud.containerID)
                    )
                    syncEnabledAtLaunch = true
                } catch {
                    // If CloudKit setup is invalid for the current signing profile, keep the app usable.
                    container = try Self.makeModelContainer(
                        schema: schema,
                        cloudKitDatabase: .none
                    )
                    syncEnabledAtLaunch = false
                    UserDefaults.standard.set(false, forKey: Constants.UserDefaultsKeys.cloudSyncEnabled)
                    print("CloudKit initialization failed; using local storage only: \(error)")
                }
            } else {
                container = try Self.makeModelContainer(
                    schema: schema,
                    cloudKitDatabase: .none
                )
                syncEnabledAtLaunch = false
            }

            self.modelContainer = container
            _settingsViewModel = State(
                initialValue: SettingsViewModel(
                    cloudSyncSupported: cloudSyncSupportedInThisBuild,
                    cloudSyncEnabledAtLaunch: syncEnabledAtLaunch
                )
            )

            NotificationService.shared.registerCategories()
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    private static func makeModelContainer(
        schema: Schema,
        cloudKitDatabase: ModelConfiguration.CloudKitDatabase
    ) throws -> ModelContainer {
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(settingsViewModel: settingsViewModel)
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1500, height: 860)
        #endif

        #if os(macOS)
        Settings {
            SettingsView(viewModel: settingsViewModel)
                .modelContainer(modelContainer)
        }
        #endif
    }
}
