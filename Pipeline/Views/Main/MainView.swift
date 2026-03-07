import SwiftUI
import SwiftData
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct MainView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var applications: [JobApplication]
    @Query private var contacts: [Contact]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedDestination: MainDestination
    @Binding var selectedApplication: JobApplication?
    @Binding var selectedContact: Contact?
    @Binding var showingAddApplication: Bool
    @Binding var showingAddContact: Bool
    @Binding var searchText: String
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
    @State private var contactsViewModel = ContactsListViewModel()
    @State private var showingSettings = false
    @State private var viewMode: ViewMode = .grid
#if os(macOS)
    @State private var escapeKeyMonitor: Any?
#endif

    private var currentApplicationFilter: SidebarFilter {
        selectedDestination.applicationFilter ?? .all
    }

    private var isApplicationsDestination: Bool {
        selectedDestination.applicationFilter != nil
    }

    private var isKanbanAvailable: Bool {
        selectedDestination == .applications(.all)
    }

    private var availableViewModes: [ViewMode] {
        isKanbanAvailable ? ViewMode.allCases : [.grid]
    }

    private var allApplicationsInclusionRule: (JobApplication) -> Bool {
        if viewMode == .grid {
            return settingsViewModel.shouldIncludeInAllApplications
        }
        return { _ in true }
    }

    private var filteredCount: Int {
        viewModel.filterApplications(
            applications,
            includeInAllApplications: allApplicationsInclusionRule
        ).count
    }

    private var filteredApplications: [JobApplication] {
        viewModel.filterApplications(
            applications,
            includeInAllApplications: allApplicationsInclusionRule
        )
    }

    private var filteredContacts: [Contact] {
        contactsViewModel.filterContacts(contacts)
    }

    private var shouldShowApplicationDetail: Bool {
        isApplicationsDestination && selectedApplication != nil
    }

    private var shouldShowContactDetail: Bool {
        selectedDestination == .contacts && selectedContact != nil
    }

    private var shouldShowDetailColumn: Bool {
        shouldShowApplicationDetail || shouldShowContactDetail
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch selectedDestination {
        case .dashboard:
            DashboardView(settingsViewModel: settingsViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .resume:
            ResumeWorkspaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .costCenter:
            CostCenterView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .contacts:
            contactsColumn
        case .applications:
            applicationsColumn
        }
    }

    private var applicationsColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text(currentApplicationFilter.displayName)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    private var contactsColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Contacts")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(filteredContacts.count) contact\(filteredContacts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            SearchBar(text: $searchText, placeholder: "Search by name, company, or email...")
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            ContactsListView(
                contacts: filteredContacts,
                selectedContact: $selectedContact,
                searchText: $searchText,
                onAddContact: {
                    showingAddContact = true
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    private var sidebarColumn: some View {
        SidebarView(
            selectedDestination: $selectedDestination,
            showingAddApplication: $showingAddApplication,
            showingAddContact: $showingAddContact,
            showingSettings: $showingSettings,
            statusCounts: viewModel.statusCounts(
                from: applications,
                includeInAllApplications: allApplicationsInclusionRule
            ),
            settingsViewModel: settingsViewModel
        )
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
    }

    @ViewBuilder
    private var detailColumn: some View {
        if shouldShowApplicationDetail, let application = selectedApplication {
            JobDetailView(
                application: application,
                onClose: {
                    closeSelectedApplication()
                },
                onSelectContact: { contact in
                    selectedDestination = .contacts
                    selectedContact = contact
                    selectedApplication = nil
                }
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 460)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
        } else if shouldShowContactDetail, let contact = selectedContact {
            ContactDetailView(
                contact: contact,
                onClose: {
                    closeSelectedContact()
                },
                onSelectApplication: { application in
                    selectedDestination = .applications(.all)
                    selectedApplication = application
                    selectedContact = nil
                }
            )
            .navigationSplitViewColumnWidth(min: 360, ideal: 460)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
        }
    }

    private var mainContentColumn: some View {
        contentColumn
            .navigationSplitViewColumnWidth(min: 520, ideal: 720)
            .navigationTitle("")
            .toolbar { mainToolbarContent }
    }

    var body: some View {
        Group {
            if shouldShowDetailColumn {
                NavigationSplitView {
                    sidebarColumn
                } content: {
                    mainContentColumn
                } detail: {
                    detailColumn
                }
            } else {
                NavigationSplitView {
                    sidebarColumn
                } detail: {
                    mainContentColumn
                }
            }
        }
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
        .sheet(isPresented: $showingAddContact) {
            ContactEditorView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel, isPresentedInSheet: true)
        }
        .onChange(of: searchText) { _, newValue in
            viewModel.searchText = newValue
            contactsViewModel.searchText = newValue
        }
        .onChange(of: selectedDestination) { _, newValue in
            if let filter = newValue.applicationFilter {
                viewModel.selectedFilter = filter
            }
            enforceViewModeAvailability()
            if newValue.applicationFilter == nil {
                closeSelectedApplication()
            }
            if newValue != .contacts {
                closeSelectedContact()
            }
        }
        .onChange(of: viewMode) { _, _ in
            enforceViewModeAvailability()
            guard selectedApplication != nil else { return }
            closeSelectedApplication()
        }
        .onAppear {
            viewModel.searchText = searchText
            viewModel.selectedFilter = currentApplicationFilter
            contactsViewModel.searchText = searchText
            enforceViewModeAvailability()
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
        if isApplicationsDestination {
            ToolbarItem(placement: .automatic) {
                Picker("View", selection: $viewMode) {
                    ForEach(availableViewModes, id: \.self) { mode in
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
        ToolbarItem(placement: .primaryAction) {
            Button {
                if selectedDestination == .contacts {
                    showingAddContact = true
                } else if isApplicationsDestination {
                    showingAddApplication = true
                }
            } label: {
                Image(systemName: selectedDestination == .contacts ? "person.badge.plus" : "plus")
            }
            .disabled(!(selectedDestination == .contacts || isApplicationsDestination))
        }
    }

#if os(macOS)
    private func installEscapeKeyMonitor() {
        guard escapeKeyMonitor == nil else { return }
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            guard !showingAddApplication, !showingAddContact, !showingSettings else { return event }

            if selectedApplication != nil {
                closeSelectedApplication()
                return nil
            }

            if selectedContact != nil {
                closeSelectedContact()
                return nil
            }

            return event
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

    private func closeSelectedApplication() {
        selectedApplication = nil
    }

    private func closeSelectedContact() {
        selectedContact = nil
    }

    private func enforceViewModeAvailability() {
        if viewMode == .kanban && !isKanbanAvailable {
            viewMode = .grid
        }
    }
}

#if os(macOS)
private extension View {
    func toolbarHandCursor() -> some View {
        onHover { isHovering in
            if isHovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}
#else
private extension View {
    func toolbarHandCursor() -> some View { self }
}
#endif
