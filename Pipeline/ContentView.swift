import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedFilter: SidebarFilter = .all
    @State private var selectedApplication: JobApplication?
    @State private var showingAddApplication = false
    @State private var searchText = ""
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        #if os(macOS)
        MainView(
            selectedFilter: $selectedFilter,
            selectedApplication: $selectedApplication,
            showingAddApplication: $showingAddApplication,
            searchText: $searchText,
            columnVisibility: $columnVisibility
        )
        #else
        NavigationStack {
            ApplicationListView(
                selectedFilter: $selectedFilter,
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
            AddApplicationView()
        }
        #endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
