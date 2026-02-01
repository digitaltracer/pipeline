import SwiftUI
import SwiftData

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var applications: [JobApplication]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedFilter: SidebarFilter
    @Binding var selectedApplication: JobApplication?
    @Binding var showingAddApplication: Bool
    @Binding var searchText: String
    @Bindable var settingsViewModel: SettingsViewModel

    @State private var viewModel = ApplicationListViewModel()

    private var filteredCount: Int {
        viewModel.filterApplications(applications).count
    }

    private var filteredApplications: [JobApplication] {
        viewModel.filterApplications(applications)
    }

    @ViewBuilder
    private var contentColumn: some View {
        VStack(spacing: 0) {
            // Section header with filter title and count
            HStack {
                Text(selectedFilter.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(filteredCount) application\(filteredCount == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            StatsBarView(stats: viewModel.calculateStats(from: applications))
                .padding(.horizontal)
                .padding(.bottom, 12)

            // Inline search bar
            SearchBar(text: $searchText, placeholder: "Search by company, role, or location...")
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            ApplicationListView(
                applications: filteredApplications,
                selectedApplication: $selectedApplication,
                searchText: $searchText
            )
        }
        // NavigationSplitView centers its child if it has an intrinsic height;
        // this pins the header/stats/search to the top like the mock.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    var body: some View {
        Group {
            if selectedApplication == nil {
                // Two-column layout until a card is selected (no empty preview column).
                NavigationSplitView {
                    SidebarView(
                        selectedFilter: $selectedFilter,
                        showingAddApplication: $showingAddApplication,
                        statusCounts: viewModel.statusCounts(from: applications),
                        settingsViewModel: settingsViewModel
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } detail: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 520, ideal: 720)
                        .navigationTitle("")
                        .toolbar {
                            ToolbarItem(placement: .automatic) {
                                Picker("Sort", selection: $viewModel.sortOrder) {
                                    ForEach(ApplicationListViewModel.SortOrder.allCases, id: \.self) { order in
                                        Text(order.rawValue).tag(order)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                }
            } else {
                // Three-column layout when an application is selected.
                NavigationSplitView {
                    SidebarView(
                        selectedFilter: $selectedFilter,
                        showingAddApplication: $showingAddApplication,
                        statusCounts: viewModel.statusCounts(from: applications),
                        settingsViewModel: settingsViewModel
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } content: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 520, ideal: 720)
                        .navigationTitle("")
                        .toolbar {
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
                        JobDetailView(application: application, onClose: {
                            selectedApplication = nil
                        })
                        .navigationSplitViewColumnWidth(min: 360, ideal: 440)
                        .background(DesignSystem.Colors.contentBackground(colorScheme))
                    }
                }
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
        .onAppear {
            viewModel.searchText = searchText
            viewModel.selectedFilter = selectedFilter
        }
    }
}

#Preview {
    MainView(
        selectedFilter: .constant(.all),
        selectedApplication: .constant(nil),
        showingAddApplication: .constant(false),
        searchText: .constant(""),
        settingsViewModel: SettingsViewModel()
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
