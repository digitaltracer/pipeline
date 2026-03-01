import SwiftUI
import SwiftData
import PipelineKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedApplication: JobApplication?
    @State private var showingAddApplication = false
    @State private var showingResume = false
    @State private var searchText = ""
    @Bindable var settingsViewModel: SettingsViewModel

    private var filteredApplications: [JobApplication] {
        let visibleApplications = applications.filter(settingsViewModel.shouldIncludeInAllApplications)
        guard !searchText.isEmpty else { return visibleApplications }
        let lowercasedSearch = searchText.lowercased()
        return visibleApplications.filter { app in
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
            showingResume: $showingResume,
            settingsViewModel: settingsViewModel
        )
        .preferredColorScheme(settingsViewModel.getColorScheme())
        .appWindowBackground()
        .task {
            prewarmJSONEditorIfNeeded()
        }
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
                    HStack(spacing: 12) {
                        Button {
                            showingResume = true
                        } label: {
                            Image(systemName: "doc.text")
                        }

                        Button {
                            showingAddApplication = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView(settingsViewModel: settingsViewModel)
        }
        .sheet(isPresented: $showingResume) {
            NavigationStack {
                ResumeWorkspaceView()
                    .navigationTitle("Resume")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showingResume = false
                            }
                        }
                    }
            }
        }
        .sheet(item: $selectedApplication) { application in
            NavigationStack {
                JobDetailView(application: application)
            }
        }
        .task {
            prewarmJSONEditorIfNeeded()
        }
        #endif
    }
}

#Preview {
    ContentView(settingsViewModel: SettingsViewModel())
        .modelContainer(
            for: [JobApplication.self, InterviewLog.self, ResumeMasterRevision.self, ResumeJobSnapshot.self],
            inMemory: true
        )
}
