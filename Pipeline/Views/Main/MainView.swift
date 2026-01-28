import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var applications: [JobApplication]

    @Binding var selectedFilter: SidebarFilter
    @Binding var selectedApplication: JobApplication?
    @Binding var showingAddApplication: Bool
    @Binding var searchText: String
    @Binding var columnVisibility: NavigationSplitViewVisibility

    @State private var viewModel = ApplicationListViewModel()

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(
                selectedFilter: $selectedFilter,
                showingAddApplication: $showingAddApplication,
                statusCounts: viewModel.statusCounts(from: applications)
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
        } content: {
            VStack(spacing: 0) {
                StatsBarView(stats: viewModel.calculateStats(from: applications))
                    .padding()

                Divider()

                ApplicationListView(
                    selectedFilter: $selectedFilter,
                    selectedApplication: $selectedApplication,
                    searchText: $searchText
                )
            }
            .navigationSplitViewColumnWidth(min: 400, ideal: 500, max: 700)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    SearchBar(text: $searchText, placeholder: "Search applications...")
                        .frame(width: 250)
                }

                ToolbarItem(placement: .automatic) {
                    Picker("Sort", selection: $viewModel.sortOrder) {
                        ForEach(ApplicationListViewModel.SortOrder.allCases, id: \.self) { order in
                            Text(order.rawValue).tag(order)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
        } detail: {
            if let application = selectedApplication {
                JobDetailView(application: application)
            } else {
                ContentUnavailableView(
                    "Select an Application",
                    systemImage: "briefcase",
                    description: Text("Choose an application from the list to view details")
                )
            }
        }
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView()
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.selectedFilter = newValue
        }
    }
}

#Preview {
    MainView(
        selectedFilter: .constant(.all),
        selectedApplication: .constant(nil),
        showingAddApplication: .constant(false),
        searchText: .constant(""),
        columnVisibility: .constant(.all)
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
