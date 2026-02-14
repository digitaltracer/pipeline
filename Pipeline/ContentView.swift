import SwiftUI
import SwiftData
import PipelineKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedApplication: JobApplication?
    @State private var showingAddApplication = false
    @State private var searchText = ""
    @Bindable var settingsViewModel: SettingsViewModel

    private var filteredApplications: [JobApplication] {
        guard !searchText.isEmpty else { return applications }
        let lowercasedSearch = searchText.lowercased()
        return applications.filter { app in
            app.companyName.lowercased().contains(lowercasedSearch) ||
            app.role.lowercased().contains(lowercasedSearch) ||
            app.location.lowercased().contains(lowercasedSearch)
        }
    }

    var body: some View {
        #if os(macOS)
        MainView(
            selectedFilter: $selectedFilter,
            selectedApplication: $selectedApplication,
            showingAddApplication: $showingAddApplication,
            searchText: $searchText,
            settingsViewModel: settingsViewModel
        )
        .preferredColorScheme(settingsViewModel.getColorScheme())
        .appWindowBackground()
        #else
        NavigationStack {
            ApplicationListView(
                applications: filteredApplications,
                selectedApplication: $selectedApplication,
                searchText: $searchText
            )
            .navigationTitle("Pipeline")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddApplication = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView(settingsViewModel: settingsViewModel)
        }
        #endif
    }
}

#Preview {
    ContentView(settingsViewModel: SettingsViewModel())
        .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
