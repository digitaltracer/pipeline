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
    @Binding var showingSettings: Bool
    @Binding var settingsEntryPoint: SettingsEntryPoint
    @Binding var searchText: String
    @Bindable var settingsViewModel: SettingsViewModel
    let onboardingStore: OnboardingStore
    let onboardingProgress: OnboardingProgress
    let onOnboardingAction: (OnboardingAction) -> Void
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

    private var offeredApplications: [JobApplication] {
        applications.filter { $0.status == .offered }
    }

    private var isOfferComparisonEnabled: Bool {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard AICompletionClient.supportsWebSearch(provider: provider, model: model) else { return false }
        return (try? settingsViewModel.apiKeys(for: provider).isEmpty == false) ?? false
    }

    private var pendingDueItemCount: Int {
        let dueCount = UpcomingItem.build(from: applications).count
        let queuedCount = ApplyQueueService().snapshot(
            from: applications,
            dailyTarget: settingsViewModel.applyQueueDailyTarget,
            currentResumeRevisionID: currentResumeRevision?.id,
            matchPreferences: settingsViewModel.jobMatchPreferences
        ).queuedCount
        return dueCount + queuedCount
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
            DashboardView(
                settingsViewModel: settingsViewModel,
                onboardingProgress: onboardingProgress,
                onOnboardingAction: onOnboardingAction,
                onHideOnboardingGuidance: {
                    onboardingStore.muteGuidance()
                }
            )
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
        case .integrations:
            IntegrationsWorkspaceView()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .offerComparison:
            OfferComparisonWorkspaceView(settingsViewModel: settingsViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .resume:
            ResumeWorkspaceView(
                onboardingProgress: onboardingProgress,
                onOnboardingAction: onOnboardingAction,
                onHideOnboardingGuidance: {
                    onboardingStore.muteGuidance()
                }
            )
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
                    matchPreferences: settingsViewModel.jobMatchPreferences,
                    onboardingProgress: onboardingProgress,
                    onOnboardingAction: onOnboardingAction,
                    onHideOnboardingGuidance: {
                        onboardingStore.muteGuidance()
                    }
                )
            case .kanban:
                KanbanBoardView(
                    applications: filteredApplications,
                    selectedApplication: $selectedApplication,
                    currentResumeRevisionID: currentResumeRevision?.id,
                    matchPreferences: settingsViewModel.jobMatchPreferences,
                    onboardingProgress: onboardingProgress,
                    onOnboardingAction: onOnboardingAction,
                    onHideOnboardingGuidance: {
                        onboardingStore.muteGuidance()
                    }
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
            applications: applications,
            selectedApplication: $selectedApplication,
            searchText: $searchText,
            settingsViewModel: settingsViewModel,
            currentResumeRevisionID: currentResumeRevision?.id,
            matchPreferences: settingsViewModel.jobMatchPreferences,
            highlightApplyQueue: pendingNotificationOpenRequest?.kind == .applyQueue
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
            settingsEntryPoint: $settingsEntryPoint,
            statusCounts: viewModel.statusCounts(
                from: applications,
                includeInAllApplications: allApplicationsInclusionRule
            ),
            upcomingCount: pendingDueItemCount,
            offeredCount: offeredApplications.count,
            isOfferComparisonEnabled: isOfferComparisonEnabled,
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
                        settingsEntryPoint = .aiProvider
                        showingSettings = true
                    }
                },
                onReplayOnboarding: {
                    onOnboardingAction(.replayTour)
                }
            )
        }
        .sheet(isPresented: $showingAddContact) {
            ContactEditorView()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(
                viewModel: settingsViewModel,
                isPresentedInSheet: true,
                entryPoint: settingsEntryPoint,
                onReplayOnboarding: {
                    onboardingStore.presentIntro(force: true)
                },
                onboardingGuidanceMuted: Binding(
                    get: { onboardingStore.guidanceMuted },
                    set: { onboardingStore.guidanceMuted = $0 }
                )
            )
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
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                settingsEntryPoint = .root
            }
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
            .fastTooltip("Change appearance")
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
            if onboardingStore.isPresentingIntro {
                onboardingStore.skipIntro()
                return nil
            }
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

    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    @Binding var searchText: String
    @Bindable var settingsViewModel: SettingsViewModel
    let currentResumeRevisionID: UUID?
    let matchPreferences: JobMatchPreferences
    var highlightApplyQueue = false

    @State private var editingTask: ApplicationTask?
    @State private var actionErrorMessage: String?
    @State private var draftingFollowUpStep: FollowUpStep?
    @State private var draftingApplication: JobApplication?
    @State private var isPreparingQueue = false

    private let viewModel = ApplicationDetailViewModel()
    private let queueService = ApplyQueueService()

    private var items: [UpcomingItem] {
        UpcomingItem.build(from: applications, searchText: searchText)
    }

    private var queueSnapshot: ApplyQueueSnapshot {
        queueService.snapshot(
            from: applications,
            dailyTarget: settingsViewModel.applyQueueDailyTarget,
            currentResumeRevisionID: currentResumeRevisionID,
            matchPreferences: matchPreferences
        )
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var filteredTodayQueue: [ApplyQueueItem] {
        filterQueueItems(queueSnapshot.todayQueue)
    }

    private var filteredBacklog: [ApplyQueueItem] {
        filterQueueItems(queueSnapshot.backlog)
    }

    private var sections: [UpcomingSection] {
        UpcomingSection.allCases.compactMap { section in
            let sectionItems = items.filter { $0.section == section }
            return sectionItems.isEmpty ? nil : section
        }
    }

    private var todaysFollowUpItems: [UpcomingItem] {
        items.filter { $0.kind == .followUp && $0.followUpStep != nil && $0.section == .today }
    }

    private var todaysActionsSummary: String {
        guard !todaysFollowUpItems.isEmpty else {
            return "No smart follow-ups are due today."
        }

        let previews = todaysFollowUpItems.prefix(3).map {
            "\($0.application.companyName) (\($0.title))"
        }
        let previewText = previews.joined(separator: ", ")
        if todaysFollowUpItems.count > 3 {
            return "You have \(todaysFollowUpItems.count) follow-ups due today: \(previewText), and more."
        }
        return "You have \(todaysFollowUpItems.count) follow-ups due today: \(previewText)."
    }

    private var queueSummaryText: String {
        let count = filteredTodayQueue.count
        guard count > 0 else {
            if normalizedSearchText.isEmpty {
                return "No queued jobs scheduled for today. Add saved jobs to the apply queue to pace your applications."
            }
            return "No queued jobs in today's queue match your search."
        }

        let readyCount = filteredTodayQueue.filter(\.preparationStatus.isReadyToApply).count
        let estimatedMinutes = filteredTodayQueue.reduce(0) { $0 + $1.estimatedMinutes }
        return "Today's apply queue: \(count) job\(count == 1 ? "" : "s"), estimated \(formattedDuration(estimatedMinutes)). \(readyCount) ready to apply."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Upcoming")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(summaryCountText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 20)
            .padding(.bottom, 12)

            SearchBar(text: $searchText, placeholder: "Search queue items, tasks, companies, or roles...")
                .padding(.horizontal)
                .padding(.bottom, 12)

            Divider()
                .overlay(DesignSystem.Colors.divider(colorScheme))

            if items.isEmpty && filteredTodayQueue.isEmpty && filteredBacklog.isEmpty {
                ContentUnavailableView {
                    Label("Nothing upcoming", systemImage: "calendar.badge.checkmark")
                } description: {
                    Text(searchText.isEmpty ? "Queued jobs, pending tasks with due dates, and follow-ups will show up here." : "No matching upcoming items.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        applyQueueHeroCard

                        if !filteredTodayQueue.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Today's Apply Queue")
                                    .font(.headline)

                                ForEach(filteredTodayQueue) { item in
                                    ApplyQueueItemCard(
                                        item: item,
                                        onOpen: {
                                            selectedApplication = item.application
                                        },
                                        onPrepare: item.preparationStatus.isReadyToApply ? nil : {
                                            Task {
                                                await prepareQueue(for: [item.application])
                                            }
                                        },
                                        onRemove: {
                                            do {
                                                try viewModel.setApplyQueueMembership(false, for: item.application, context: modelContext)
                                            } catch {
                                                actionErrorMessage = error.localizedDescription
                                            }
                                        },
                                        onMarkApplied: {
                                            do {
                                                _ = try viewModel.markAppliedFromQueue(for: item.application, context: modelContext)
                                            } catch {
                                                actionErrorMessage = error.localizedDescription
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        if !filteredBacklog.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Queued Backlog")
                                    .font(.headline)

                                ForEach(filteredBacklog) { item in
                                    ApplyQueueItemCard(
                                        item: item,
                                        onOpen: {
                                            selectedApplication = item.application
                                        },
                                        onPrepare: item.preparationStatus.isReadyToApply ? nil : {
                                            Task {
                                                await prepareQueue(for: [item.application])
                                            }
                                        },
                                        onRemove: {
                                            do {
                                                try viewModel.setApplyQueueMembership(false, for: item.application, context: modelContext)
                                            } catch {
                                                actionErrorMessage = error.localizedDescription
                                            }
                                        },
                                        onMarkApplied: {
                                            do {
                                                _ = try viewModel.markAppliedFromQueue(for: item.application, context: modelContext)
                                            } catch {
                                                actionErrorMessage = error.localizedDescription
                                            }
                                        }
                                    )
                                }
                            }
                        }

                        if !items.isEmpty {
                            todaysActionsCard

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
                                            onGenerateFollowUp: item.followUpStep?.kind.supportsDraftGeneration == true ? {
                                                draftingFollowUpStep = item.followUpStep
                                                draftingApplication = item.application
                                            } : nil,
                                            onSnoozeFollowUp: item.followUpStep.map { step in
                                                {
                                                    do {
                                                        try viewModel.snoozeFollowUpStep(
                                                            step,
                                                            by: item.snoozeDays,
                                                            for: item.application,
                                                            context: modelContext
                                                        )
                                                    } catch {
                                                        actionErrorMessage = error.localizedDescription
                                                    }
                                                }
                                            },
                                            onMarkFollowUpDone: item.followUpStep.map { step in
                                                {
                                                    do {
                                                        try viewModel.markFollowUpStepDone(step, for: item.application, context: modelContext)
                                                    } catch {
                                                        actionErrorMessage = error.localizedDescription
                                                    }
                                                }
                                            },
                                            onDismissFollowUp: item.followUpStep?.kind == .archiveSuggestion ? {
                                                guard let step = item.followUpStep else { return }
                                                do {
                                                    try viewModel.dismissFollowUpStep(step, for: item.application, context: modelContext)
                                                } catch {
                                                    actionErrorMessage = error.localizedDescription
                                                }
                                            } : nil,
                                            onArchiveApplication: item.followUpStep?.kind == .archiveSuggestion ? {
                                                do {
                                                    try viewModel.archive(item.application, context: modelContext)
                                                } catch {
                                                    actionErrorMessage = error.localizedDescription
                                                }
                                            } : nil,
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
        .sheet(item: $draftingApplication) { application in
            FollowUpDrafterView(
                viewModel: FollowUpDrafterViewModel(
                    application: application,
                    settingsViewModel: settingsViewModel,
                    modelContext: modelContext,
                    followUpStep: draftingFollowUpStep
                )
            )
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

    private var summaryCountText: String {
        let queuedCount = filteredTodayQueue.count + filteredBacklog.count
        let dueCount = items.count
        if queuedCount > 0 && dueCount > 0 {
            return "\(queuedCount) queued • \(dueCount) due"
        }
        if queuedCount > 0 {
            return "\(queuedCount) queued job\(queuedCount == 1 ? "" : "s")"
        }
        return "\(dueCount) due item\(dueCount == 1 ? "" : "s")"
    }

    private var applyQueueHeroCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Today's Apply Queue", systemImage: "bookmark.circle.fill")
                        .font(.headline)
                    Text(queueSummaryText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if !filteredTodayQueue.isEmpty {
                    Text("\(filteredTodayQueue.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if !filteredTodayQueue.isEmpty {
                HStack(spacing: 12) {
                    Button(isPreparingQueue ? "Preparing..." : "Prepare All") {
                        Task {
                            await prepareQueue(for: filteredTodayQueue.map(\.application))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(isPreparingQueue)

                    if !filteredTodayQueue.filter(\.preparationStatus.isReadyToApply).isEmpty {
                        Text("\(filteredTodayQueue.filter(\.preparationStatus.isReadyToApply).count) ready now")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.green)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    highlightApplyQueue ? DesignSystem.Colors.accent : DesignSystem.Colors.stroke(colorScheme),
                    lineWidth: highlightApplyQueue ? 2 : 1
                )
        )
    }

    private var todaysActionsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Today's Actions", systemImage: "sun.max")
                    .font(.headline)

                Spacer()

                Text("\(todaysFollowUpItems.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DesignSystem.Colors.accent.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(todaysActionsSummary)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }

    private func prepareQueue(for applications: [JobApplication]) async {
        guard !applications.isEmpty else { return }
        isPreparingQueue = true
        let results = await ApplyQueuePreparationCoordinator.shared.prepare(
            applications: applications,
            modelContext: modelContext,
            settingsViewModel: settingsViewModel
        )
        isPreparingQueue = false

        let failureMessages = results.flatMap(\.messages)
        if let firstMessage = failureMessages.first {
            actionErrorMessage = firstMessage
        }
    }

    private func filterQueueItems(_ items: [ApplyQueueItem]) -> [ApplyQueueItem] {
        guard !normalizedSearchText.isEmpty else { return items }

        return items.filter { item in
            let candidates = [
                item.application.role,
                item.application.companyName,
                item.application.location,
                item.preparationStatus.missingPreparationTitles.joined(separator: " ")
            ]
            .map { $0.lowercased() }

            return candidates.contains { $0.contains(normalizedSearchText) }
        }
    }
}

private struct ApplyQueueItemCard: View {
    let item: ApplyQueueItem
    var onOpen: () -> Void
    var onPrepare: (() -> Void)?
    var onRemove: () -> Void
    var onMarkApplied: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: item.preparationStatus.isReadyToApply ? "checkmark.circle.fill" : "bookmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(item.preparationStatus.isReadyToApply ? .green : .blue)
                    .frame(width: 18, height: 18)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.application.role)
                            .font(.subheadline.weight(.semibold))

                        PriorityFlag(priority: item.application.priority)
                    }

                    Text("\(item.application.companyName) • \(item.application.location)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(preparationSummary)
                        .font(.caption)
                        .foregroundColor(item.preparationStatus.isReadyToApply ? .green : .secondary)

                    HStack(spacing: 8) {
                        badge(text: "Est. \(formattedDuration(item.estimatedMinutes))", tint: .orange)

                        if let score = item.freshMatchScore {
                            badge(text: "Match \(score)%", tint: .blue)
                        } else if item.isMatchScoreStale {
                            badge(text: "Match stale", tint: .secondary)
                        } else {
                            badge(text: "Unscored", tint: .secondary)
                        }

                        if let deadline = item.applicationDeadline {
                            badge(text: "Due \(deadline.formatted(date: .abbreviated, time: .omitted))", tint: deadline < Date() ? .red : .pink)
                        } else if let postedAt = item.postedAt {
                            badge(text: "Posted \(postedAt.formatted(date: .abbreviated, time: .omitted))", tint: .teal)
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: 12) {
                Button("Open") {
                    onOpen()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)

                if let onPrepare {
                    Button("Prepare Now") {
                        onPrepare()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }

                Button("Mark Applied") {
                    onMarkApplied()
                }
                .buttonStyle(.plain)
                .foregroundColor(.blue)

                Button("Remove") {
                    onRemove()
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                Spacer()
            }
            .font(.caption)
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private var preparationSummary: String {
        if item.preparationStatus.isReadyToApply {
            return "Ready to apply"
        }

        return "Prep needed: \(item.preparationStatus.missingPreparationTitles.joined(separator: ", "))"
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }

    private func formattedDuration(_ minutes: Int) -> String {
        if minutes >= 60 {
            let hours = minutes / 60
            let remainder = minutes % 60
            return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
        }
        return "\(minutes)m"
    }
}

private struct UpcomingItemRow: View {
    let item: UpcomingItem
    var onOpen: () -> Void
    var onCompleteTask: (() -> Void)? = nil
    var onEditTask: (() -> Void)? = nil
    var onDeleteTask: (() -> Void)? = nil
    var onGenerateFollowUp: (() -> Void)? = nil
    var onSnoozeFollowUp: (() -> Void)? = nil
    var onMarkFollowUpDone: (() -> Void)? = nil
    var onDismissFollowUp: (() -> Void)? = nil
    var onArchiveApplication: (() -> Void)? = nil
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

                if let onGenerateFollowUp {
                    Button("Generate") {
                        onGenerateFollowUp()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)
                }

                if let onSnoozeFollowUp {
                    Button("Snooze \(item.snoozeDays) Days") {
                        onSnoozeFollowUp()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                }

                if let onMarkFollowUpDone {
                    Button("Mark Done") {
                        onMarkFollowUpDone()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.green)
                }

                if let onArchiveApplication {
                    Button("Archive") {
                        onArchiveApplication()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.orange)
                }

                if let onDismissFollowUp {
                    Button("Dismiss") {
                        onDismissFollowUp()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
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
    let followUpStep: FollowUpStep?
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

    var snoozeDays: Int {
        switch followUpStep?.kind {
        case .archiveSuggestion:
            return 7
        case .none:
            return 3
        default:
            return 3
        }
    }

    static func build(from applications: [JobApplication], searchText: String = "") -> [UpcomingItem] {
        let lowercasedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let items = applications
            .filter { $0.status != .archived }
            .flatMap { application -> [UpcomingItem] in
                var applicationItems: [UpcomingItem] = []

                if !application.activeFollowUpSteps.isEmpty {
                    applicationItems.append(
                        contentsOf: application.activeFollowUpSteps.map { step in
                            UpcomingItem(
                                id: "followup-\(step.id.uuidString)",
                                kind: .followUp,
                                application: application,
                                task: nil,
                                followUpStep: step,
                                title: step.kind.displayName,
                                notes: step.kind.rationaleText,
                                dueDate: step.dueDate,
                                priority: application.priority
                            )
                        }
                    )
                } else if let followUpDate = application.nextFollowUpDate {
                    applicationItems.append(
                        UpcomingItem(
                            id: "followup-\(application.id.uuidString)",
                            kind: .followUp,
                            application: application,
                            task: nil,
                            followUpStep: nil,
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
                        followUpStep: nil,
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

            if lhs.kind != rhs.kind {
                return lhs.kind == .followUp && rhs.kind == .task
            }

            if lhs.followUpStep?.sequenceIndex != rhs.followUpStep?.sequenceIndex {
                return (lhs.followUpStep?.sequenceIndex ?? Int.max) < (rhs.followUpStep?.sequenceIndex ?? Int.max)
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
