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
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]
    @Environment(\.colorScheme) private var colorScheme

    @Binding var selectedDestination: MainDestination
    @Binding var selectedApplication: JobApplication?
    @Binding var selectedContact: Contact?
    @Binding var showingAddApplication: Bool
    @Binding var showingAddContact: Bool
    @Binding var searchText: String
    @Bindable var settingsViewModel: SettingsViewModel
    var pendingNotificationOpenRequest: NotificationOpenRequest? = nil
    var onHandledNotificationOpenRequest: (() -> Void)? = nil

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
            currentResumeRevisionID: currentResumeRevision?.id,
            matchPreferences: settingsViewModel.jobMatchPreferences,
            includeInAllApplications: allApplicationsInclusionRule
        ).count
    }

    private var filteredApplications: [JobApplication] {
        viewModel.filterApplications(
            applications,
            currentResumeRevisionID: currentResumeRevision?.id,
            matchPreferences: settingsViewModel.jobMatchPreferences,
            includeInAllApplications: allApplicationsInclusionRule
        )
    }

    private var currentResumeRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    private var staleMatchCount: Int {
        let preferences = settingsViewModel.jobMatchPreferences
        return applications.filter { application in
            guard let assessment = application.matchAssessment else { return false }
            return JobMatchScoringService.isStale(
                assessment,
                application: application,
                currentResumeRevisionID: currentResumeRevision?.id,
                preferences: preferences
            )
        }.count
    }

    private var jobMatchRefreshToken: String {
        let applicationToken = applications.map { application in
            let assessmentUpdatedAt = application.matchAssessment?.updatedAt.timeIntervalSinceReferenceDate ?? 0
            return "\(application.id.uuidString)-\(application.updatedAt.timeIntervalSinceReferenceDate)-\(assessmentUpdatedAt)"
        }.joined(separator: "|")
        return "\(currentResumeRevision?.id.uuidString ?? "none")|\(settingsViewModel.jobMatchPreferences.fingerprint)|\(applicationToken)"
    }

    private var filteredContacts: [Contact] {
        contactsViewModel.filterContacts(contacts)
    }

    private var upcomingItems: [UpcomingItem] {
        UpcomingItem.build(from: applications, searchText: searchText)
    }

    private var pendingDueItemCount: Int {
        UpcomingItem.build(from: applications).count
    }

    private var shouldShowApplicationDetail: Bool {
        (isApplicationsDestination || selectedDestination == .upcoming) && selectedApplication != nil
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
        case .weeklyDigest:
            WeeklyDigestView(
                settingsViewModel: settingsViewModel,
                onOpenApplication: { application in
                    selectedDestination = .applications(.all)
                    selectedApplication = application
                },
                highlightedDigestID: pendingNotificationOpenRequest?.weeklyDigestSnapshotID,
                onHandledNotificationOpenRequest: onHandledNotificationOpenRequest
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .upcoming:
            upcomingColumn
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

                if staleMatchCount > 0 {
                    Button("Refresh \(staleMatchCount) Stale Score\(staleMatchCount == 1 ? "" : "s")") {
                        Task {
                            await JobMatchScoringCoordinator.shared.refreshAllStaleApplications(
                                applications,
                                modelContext: modelContext,
                                settingsViewModel: settingsViewModel
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                }
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
                    searchText: $searchText,
                    currentResumeRevisionID: currentResumeRevision?.id,
                    matchPreferences: settingsViewModel.jobMatchPreferences
                )
            case .kanban:
                KanbanBoardView(
                    applications: filteredApplications,
                    selectedApplication: $selectedApplication,
                    currentResumeRevisionID: currentResumeRevision?.id,
                    matchPreferences: settingsViewModel.jobMatchPreferences
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

    private var upcomingColumn: some View {
        UpcomingView(
            items: upcomingItems,
            selectedApplication: $selectedApplication,
            searchText: $searchText
        )
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
            upcomingCount: pendingDueItemCount,
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
                },
                pendingNotificationOpenRequest: pendingNotificationOpenRequest,
                onHandledNotificationOpenRequest: onHandledNotificationOpenRequest
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
            if newValue.applicationFilter == nil && newValue != .upcoming {
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
        .task(id: jobMatchRefreshToken) {
            await JobMatchScoringCoordinator.shared.processEligibleApplications(
                applications,
                modelContext: modelContext,
                settingsViewModel: settingsViewModel
            )
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
            ToolbarItem(placement: .automatic) {
                Picker("Score Filter", selection: $viewModel.matchScoreFilter) {
                    ForEach(ApplicationListViewModel.MatchScoreFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .toolbarHandCursor()
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

struct UpcomingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let items: [UpcomingItem]
    @Binding var selectedApplication: JobApplication?
    @Binding var searchText: String

    @State private var editingTask: ApplicationTask?
    @State private var actionErrorMessage: String?

    private let viewModel = ApplicationDetailViewModel()

    private var sections: [UpcomingSection] {
        UpcomingSection.allCases.compactMap { section in
            let sectionItems = items.filter { $0.section == section }
            return sectionItems.isEmpty ? nil : section
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Upcoming")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("\(items.count) due item\(items.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            SearchBar(text: $searchText, placeholder: "Search tasks, companies, or roles...")
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            if items.isEmpty {
                ContentUnavailableView {
                    Label("Nothing upcoming", systemImage: "calendar.badge.checkmark")
                } description: {
                    Text(searchText.isEmpty ? "Pending tasks with due dates and follow-ups will show up here." : "No matching upcoming items.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(sections, id: \.self) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(section.title)
                                    .font(.headline)

                                ForEach(items.filter { $0.section == section }) { item in
                                    UpcomingItemRow(
                                        item: item,
                                        onOpen: {
                                            selectedApplication = item.application
                                        },
                                        onCompleteTask: item.task.map { task in
                                            {
                                                do {
                                                    try viewModel.setTaskCompletion(true, for: task, in: item.application, context: modelContext)
                                                } catch {
                                                    actionErrorMessage = error.localizedDescription
                                                }
                                            }
                                        },
                                        onEditTask: item.task.map { task in
                                            { editingTask = task }
                                        },
                                        onDeleteTask: item.task.map { task in
                                            {
                                                do {
                                                    try viewModel.deleteTask(task, from: item.application, context: modelContext)
                                                } catch {
                                                    actionErrorMessage = error.localizedDescription
                                                }
                                            }
                                        },
                                        onClearFollowUp: item.kind == .followUp ? {
                                            do {
                                                try viewModel.clearFollowUp(for: item.application, context: modelContext)
                                            } catch {
                                                actionErrorMessage = error.localizedDescription
                                            }
                                        } : nil
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .sheet(item: $editingTask) { task in
            if let application = task.application {
                ApplicationTaskEditorView(application: application, taskToEdit: task)
            }
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
    }
}

private struct UpcomingItemRow: View {
    let item: UpcomingItem
    var onOpen: () -> Void
    var onCompleteTask: (() -> Void)? = nil
    var onEditTask: (() -> Void)? = nil
    var onDeleteTask: (() -> Void)? = nil
    var onClearFollowUp: (() -> Void)? = nil

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(item.tintColor)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))

                        PriorityFlag(priority: item.priority)
                    }

                    Text("\(item.application.companyName) • \(item.application.role)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let notes = item.notes {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                Text(item.dueDateLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(item.dueTintColor)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(item.dueTintColor.opacity(0.12))
                    .clipShape(Capsule())
            }

            HStack(spacing: 12) {
                Button("Open") {
                    onOpen()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)

                if let onCompleteTask {
                    Button("Complete") {
                        onCompleteTask()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }

                if let onClearFollowUp {
                    Button("Done") {
                        onClearFollowUp()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }

                if let onEditTask {
                    Button("Edit") {
                        onEditTask()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)
                }

                if let onDeleteTask {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        "Delete Task",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Delete", role: .destructive) {
                            onDeleteTask()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to delete this task?")
                    }
                }

                Spacer()
            }
            .font(.caption)
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

enum UpcomingSection: CaseIterable {
    case overdue
    case today
    case soon
    case later

    var title: String {
        switch self {
        case .overdue:
            return "Overdue"
        case .today:
            return "Today"
        case .soon:
            return "Soon"
        case .later:
            return "Later"
        }
    }
}

struct UpcomingItem: Identifiable {
    enum Kind {
        case task
        case followUp
    }

    let id: String
    let kind: Kind
    let application: JobApplication
    let task: ApplicationTask?
    let title: String
    let notes: String?
    let dueDate: Date
    let priority: Priority

    var section: UpcomingSection {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDueDay = calendar.startOfDay(for: dueDate)

        if startOfDueDay < startOfToday {
            return .overdue
        }

        if calendar.isDateInToday(dueDate) {
            return .today
        }

        let startOfSoonBoundary = calendar.date(byAdding: .day, value: 7, to: startOfToday) ?? startOfToday
        if startOfDueDay < startOfSoonBoundary {
            return .soon
        }

        return .later
    }

    var icon: String {
        switch kind {
        case .task:
            return "checklist"
        case .followUp:
            return "calendar.badge.clock"
        }
    }

    var tintColor: Color {
        switch kind {
        case .task:
            return priority.color
        case .followUp:
            return .orange
        }
    }

    var dueTintColor: Color {
        section == .overdue ? .red : tintColor
    }

    var dueDateLabel: String {
        switch section {
        case .overdue:
            return "Overdue"
        case .today:
            return "Today"
        case .soon, .later:
            return dueDate.formatted(date: .abbreviated, time: .omitted)
        }
    }

    static func build(from applications: [JobApplication], searchText: String = "") -> [UpcomingItem] {
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let items = applications
            .filter { $0.status != .archived }
            .flatMap { application -> [UpcomingItem] in
                var applicationItems: [UpcomingItem] = []

                if let followUpDate = application.nextFollowUpDate {
                    applicationItems.append(
                        UpcomingItem(
                            id: "followup-\(application.id.uuidString)",
                            kind: .followUp,
                            application: application,
                            task: nil,
                            title: "Follow up with \(application.companyName)",
                            notes: nil,
                            dueDate: followUpDate,
                            priority: application.priority
                        )
                    )
                }

                let taskItems = application.sortedTasks.compactMap { task -> UpcomingItem? in
                    guard !task.isCompleted, let dueDate = task.dueDate else { return nil }

                    return UpcomingItem(
                        id: "task-\(task.id.uuidString)",
                        kind: .task,
                        application: application,
                        task: task,
                        title: task.displayTitle,
                        notes: task.normalizedNotes,
                        dueDate: dueDate,
                        priority: task.priority
                    )
                }

                applicationItems.append(contentsOf: taskItems)
                return applicationItems
            }

        let filteredItems: [UpcomingItem]
        if lowercasedSearch.isEmpty {
            filteredItems = items
        } else {
            filteredItems = items.filter { item in
                item.title.lowercased().contains(lowercasedSearch) ||
                item.application.companyName.lowercased().contains(lowercasedSearch) ||
                item.application.role.lowercased().contains(lowercasedSearch) ||
                (item.notes?.lowercased().contains(lowercasedSearch) ?? false)
            }
        }

        return filteredItems.sorted { lhs, rhs in
            if lhs.dueDate != rhs.dueDate {
                return lhs.dueDate < rhs.dueDate
            }

            if lhs.priority.sortOrder != rhs.priority.sortOrder {
                return lhs.priority.sortOrder < rhs.priority.sortOrder
            }

            if lhs.application.companyName != rhs.application.companyName {
                return lhs.application.companyName.localizedCaseInsensitiveCompare(rhs.application.companyName) == .orderedAscending
            }

            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
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
