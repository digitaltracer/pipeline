import SwiftUI
import SwiftData

@main
struct PipelineApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([
                JobApplication.self,
                InterviewLog.self
            ])

            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private("iCloud.com.pipeline.app")
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
        .defaultSize(width: 1200, height: 800)
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .modelContainer(modelContainer)
        }
        #endif
    }
}
