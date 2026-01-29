import SwiftUI
import SwiftData

// MARK: - Development Flag
// Set to false to disable CloudKit/iCloud sync (works with Personal Team provisioning).
// To re-enable later:
// 1) Switch CODE_SIGN_ENTITLEMENTS to `Pipeline.CloudKit.entitlements` in Xcode, and
// 2) Set this flag to true.
private let enableCloudKitSync = false

@main
struct PipelineApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                JobApplication.self,
                InterviewLog.self
            ])

            let cloudKitConfig: ModelConfiguration.CloudKitDatabase = enableCloudKitSync
                ? .private("iCloud.com.pipeline.app")
                : .none

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: cloudKitConfig
            )

            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1500, height: 860)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #endif
    }
}
