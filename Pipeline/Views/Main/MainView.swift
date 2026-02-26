import SwiftUI
import SwiftData
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var applications: [JobApplication]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedFilter: SidebarFilter
    @Binding var selectedApplication: JobApplication?
    @Binding var showingAddApplication: Bool
    @Binding var searchText: String
    @Binding var showingResume: Bool
    @Bindable var settingsViewModel: SettingsViewModel

    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case kanban = "Kanban"

        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .kanban: return "rectangle.split.3x1"
            }
        }
    }

    @State private var viewModel = ApplicationListViewModel()
    @State private var showingSettings = false
    @State private var showingDashboard = false
    @State private var viewMode: ViewMode = .grid
    private let detailCloseAnimation: Animation = .easeInOut(duration: 0.22)
#if os(macOS)
    @State private var escapeKeyMonitor: Any?
#endif

    private var filteredCount: Int {
        viewModel.filterApplications(applications).count
    }

    private var filteredApplications: [JobApplication] {
        viewModel.filterApplications(applications)
    }

    @ViewBuilder
    private var contentColumn: some View {
        if showingDashboard {
            DashboardView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if showingResume {
            ResumeWorkspaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
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

                StatsBarView(
                    stats: viewModel.calculateStats(from: applications),
                    isDetailPanelOpen: selectedApplication != nil
                )
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                // Inline search bar
                SearchBar(text: $searchText, placeholder: "Search by company, role, or location...")
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                Divider()
                    .overlay(DesignSystem.Colors.divider(colorScheme))

                switch viewMode {
                case .grid:
                    ApplicationListView(
                        applications: filteredApplications,
                        selectedApplication: $selectedApplication,
                        searchText: $searchText
                    )
                case .kanban:
                    KanbanBoardView(
                        applications: filteredApplications,
                        selectedApplication: $selectedApplication
                    )
                }
            }
            // NavigationSplitView centers its child if it has an intrinsic height;
            // this pins the header/stats/search to the top like the mock.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
        }
    }

    var body: some View {
        Group {
            if selectedApplication == nil {
                // Two-column layout until a card is selected (no empty preview column).
                NavigationSplitView {
                    SidebarView(
                        selectedFilter: $selectedFilter,
                        showingAddApplication: $showingAddApplication,
                        showingSettings: $showingSettings,
                        showingDashboard: $showingDashboard,
                        showingResume: $showingResume,
                        statusCounts: viewModel.statusCounts(from: applications),
                        settingsViewModel: settingsViewModel
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } detail: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 520, ideal: 720)
                        .navigationTitle("")
                        .toolbar { mainToolbarContent }
                }
            } else {
                // Three-column layout when an application is selected.
                NavigationSplitView {
                    SidebarView(
                        selectedFilter: $selectedFilter,
                        showingAddApplication: $showingAddApplication,
                        showingSettings: $showingSettings,
                        showingDashboard: $showingDashboard,
                        showingResume: $showingResume,
                        statusCounts: viewModel.statusCounts(from: applications),
                        settingsViewModel: settingsViewModel
                    )
                    .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
                } content: {
                    contentColumn
                        .navigationSplitViewColumnWidth(min: 520, ideal: 720)
                        .navigationTitle("")
                        .toolbar { mainToolbarContent }
                } detail: {
                    if let application = selectedApplication {
                        JobDetailView(application: application, onClose: {
                            closeSelectedApplicationWithAnimation()
                        })
                        .navigationSplitViewColumnWidth(min: 360, ideal: 440)
                        .background(DesignSystem.Colors.contentBackground(colorScheme))
                    }
                }
            }
        }
        .animation(detailCloseAnimation, value: selectedApplication?.id)
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView(
                settingsViewModel: settingsViewModel,
                onOpenSettings: {
                    showingAddApplication = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        showingSettings = true
                    }
                }
            )
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel, isPresentedInSheet: true)
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
        }
        .onChange(of: selectedFilter) { _, newValue in
            viewModel.selectedFilter = newValue
        }
        .onChange(of: showingResume) { _, isShowingResume in
            guard isShowingResume, selectedApplication != nil else { return }
            closeSelectedApplicationWithAnimation()
        }
        .onAppear {
            viewModel.searchText = searchText
            viewModel.selectedFilter = selectedFilter
#if os(macOS)
            installEscapeKeyMonitor()
#endif
        }
#if os(macOS)
        .onDisappear {
            removeEscapeKeyMonitor()
        }
#endif
    }

    @ToolbarContentBuilder
    private var mainToolbarContent: some ToolbarContent {
#if os(macOS)
        ToolbarItem(placement: .navigation) {
            Button {
                withAnimation {
                    cycleTheme()
                }
            } label: {
                Image(systemName: settingsViewModel.appearanceMode.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 32)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
            .toolbarHandCursor()
            .help("Change appearance")
        }
#endif
        ToolbarItem(placement: .automatic) {
            Picker("View", selection: $viewMode) {
                ForEach(ViewMode.allCases, id: \.self) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .toolbarHandCursor()
        }
        ToolbarItem(placement: .automatic) {
            Picker("Sort", selection: $viewModel.sortOrder) {
                ForEach(ApplicationListViewModel.SortOrder.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.menu)
            .toolbarHandCursor()
            .padding(.horizontal, 6)
        }
    }

#if os(macOS)
    private func installEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // Escape
            guard !showingAddApplication, !showingSettings else { return event }
            guard selectedApplication != nil else { return event }

            closeSelectedApplicationWithAnimation()
            return nil
        }
    }

    private func removeEscapeKeyMonitor() {
        guard let escapeKeyMonitor else { return }
        NSEvent.removeMonitor(escapeKeyMonitor)
        self.escapeKeyMonitor = nil
    }
#endif

    private func cycleTheme() {
        switch settingsViewModel.appearanceMode {
        case .system:
            settingsViewModel.appearanceMode = .light
        case .light:
            settingsViewModel.appearanceMode = .dark
        case .dark:
            settingsViewModel.appearanceMode = .system
        }
    }

    private func closeSelectedApplicationWithAnimation() {
        withAnimation(detailCloseAnimation) {
            selectedApplication = nil
        }
    }
}

private extension View {
#if os(macOS)
    func toolbarHandCursor() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
#else
    func toolbarHandCursor() -> some View { self }
#endif
}

#Preview {
    MainView(
        selectedFilter: .constant(.all),
        selectedApplication: .constant(nil),
        showingAddApplication: .constant(false),
        searchText: .constant(""),
        showingResume: .constant(false),
        settingsViewModel: SettingsViewModel()
    )
    .modelContainer(
        for: [JobApplication.self, InterviewLog.self, ResumeMasterRevision.self, ResumeJobSnapshot.self],
        inMemory: true
    )
}
