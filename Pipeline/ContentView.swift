import SwiftUI
import SwiftData
import PipelineKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \Contact.updatedAt, order: .reverse) private var contacts: [Contact]
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]
    @Query(sort: \WeeklyDigestSnapshot.weekStart, order: .reverse) private var weeklyDigests: [WeeklyDigestSnapshot]
    @State private var selectedDestination: MainDestination = .applications(.all)
    @State private var selectedApplication: JobApplication?
    @State private var selectedContact: Contact?
    @State private var showingAddApplication = false
    @State private var showingAddContact = false
    @State private var showingSettings = false
    @State private var searchText = ""
    @State private var pendingNotificationOpenRequest: NotificationOpenRequest?
    @Bindable var settingsViewModel: SettingsViewModel

    private let weeklyDigestService = WeeklyDigestService()

    private var filteredApplications: [JobApplication] {
        let visibleApplications: [JobApplication]
        if let filter = selectedDestination.applicationFilter, filter != .all, let status = filter.status {
            visibleApplications = applications.filter { $0.status == status }
        } else {
            visibleApplications = applications.filter(settingsViewModel.shouldIncludeInAllApplications)
        }

        guard !searchText.isEmpty else { return visibleApplications }
        let lowercasedSearch = searchText.lowercased()
        return visibleApplications.filter { app in
            app.companyName.lowercased().contains(lowercasedSearch) ||
            app.role.lowercased().contains(lowercasedSearch) ||
            app.location.lowercased().contains(lowercasedSearch)
        }
    }

    private var filteredContacts: [Contact] {
        guard !searchText.isEmpty else { return contacts }
        let lowercasedSearch = searchText.lowercased()
        return contacts.filter { contact in
            contact.fullName.lowercased().contains(lowercasedSearch) ||
            (contact.companyName?.lowercased().contains(lowercasedSearch) ?? false) ||
            (contact.email?.lowercased().contains(lowercasedSearch) ?? false)
        }
    }

    private var currentResumeRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    var body: some View {
        #if os(macOS)
        MainView(
            selectedDestination: $selectedDestination,
            selectedApplication: $selectedApplication,
            selectedContact: $selectedContact,
            showingAddApplication: $showingAddApplication,
            showingAddContact: $showingAddContact,
            searchText: $searchText,
            settingsViewModel: settingsViewModel,
            pendingNotificationOpenRequest: pendingNotificationOpenRequest,
            onHandledNotificationOpenRequest: {
                pendingNotificationOpenRequest = nil
            }
        )
        .preferredColorScheme(settingsViewModel.getColorScheme())
        .appWindowBackground()
        .task {
            prewarmJSONEditorIfNeeded()
            await configureNotificationRouting()
            await syncNotifications()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await syncNotifications()
            }
        }
        #else
        NavigationStack {
            Group {
                switch selectedDestination {
                case .dashboard:
                    DashboardView(settingsViewModel: settingsViewModel)
                case .weeklyDigest:
                    WeeklyDigestView(
                        settingsViewModel: settingsViewModel,
                        onOpenApplication: { application in
                            selectedDestination = .applications(.all)
                            selectedApplication = application
                        },
                        highlightedDigestID: pendingNotificationOpenRequest?.weeklyDigestSnapshotID,
                        onHandledNotificationOpenRequest: {
                            pendingNotificationOpenRequest = nil
                        }
                    )
                case .upcoming:
                    UpcomingView(
                        items: UpcomingItem.build(from: applications, searchText: searchText),
                        selectedApplication: $selectedApplication,
                        searchText: $searchText
                    )
                case .contacts:
                    ContactsListView(
                        contacts: filteredContacts,
                        selectedContact: $selectedContact,
                        searchText: $searchText,
                        onAddContact: {
                            showingAddContact = true
                        }
                    )
                case .resume:
                    ResumeWorkspaceView()
                case .costCenter:
                    CostCenterView()
                case .applications:
                    ApplicationListView(
                        applications: filteredApplications,
                        selectedApplication: $selectedApplication,
                        searchText: $searchText,
                        currentResumeRevisionID: nil,
                        matchPreferences: settingsViewModel.jobMatchPreferences
                    )
                }
            }
            .navigationTitle(selectedDestination.title)
            .searchable(text: $searchText)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Dashboard") { selectedDestination = .dashboard }
                        Button("Weekly Digest") { selectedDestination = .weeklyDigest }
                        Button("Upcoming") { selectedDestination = .upcoming }
                        Divider()
                        ForEach(SidebarFilter.allCases) { filter in
                            Button(filter.displayName) {
                                selectedDestination = .applications(filter)
                            }
                        }
                        Divider()
                        Button("Contacts") { selectedDestination = .contacts }
                        Button("Resume") { selectedDestination = .resume }
                        Button("Cost Center") { selectedDestination = .costCenter }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            if selectedDestination == .contacts {
                                showingAddContact = true
                            } else if selectedDestination.applicationFilter != nil {
                                showingAddApplication = true
                            } else {
                                selectedDestination = .applications(.all)
                            }
                        } label: {
                            Image(systemName: selectedDestination == .contacts ? "person.badge.plus" : "plus")
                        }

                        Button {
                            showingSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddApplication) {
            AddApplicationView(settingsViewModel: settingsViewModel)
        }
        .sheet(isPresented: $showingAddContact) {
            ContactEditorView()
        }
        .sheet(item: $selectedApplication) { application in
            NavigationStack {
                JobDetailView(
                    application: application,
                    onSelectContact: { contact in
                        selectedDestination = .contacts
                        selectedContact = contact
                    },
                    pendingNotificationOpenRequest: pendingNotificationOpenRequest,
                    onHandledNotificationOpenRequest: {
                        pendingNotificationOpenRequest = nil
                    }
                )
            }
        }
        .sheet(item: $selectedContact) { contact in
            NavigationStack {
                ContactDetailView(contact: contact)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(viewModel: settingsViewModel, isPresentedInSheet: true)
        }
        .task {
            prewarmJSONEditorIfNeeded()
            await configureNotificationRouting()
            await syncNotifications()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await syncNotifications()
            }
        }
        #endif
    }

    @MainActor
    private func configureNotificationRouting() async {
        NotificationService.shared.setOpenRequestHandler { request in
            handleNotificationOpenRequest(request)
        }

        if let pendingRequest = NotificationService.shared.consumePendingOpenRequest() {
            handleNotificationOpenRequest(pendingRequest)
        }
    }

    @MainActor
    private func handleNotificationOpenRequest(_ request: NotificationOpenRequest) {
        selectedContact = nil

        switch request.kind {
        case .interviewDebrief:
            selectedDestination = .applications(.all)
            if let applicationID = request.applicationID {
                selectedApplication = applications.first(where: { $0.id == applicationID })
            }
        case .weeklyDigest:
            selectedDestination = .weeklyDigest
            selectedApplication = nil
        }

        pendingNotificationOpenRequest = request
    }

    @MainActor
    private func syncNotifications(referenceDate: Date = Date()) async {
        await NotificationService.shared.syncReminderState(
            for: applications,
            notificationsEnabled: settingsViewModel.notificationsEnabled,
            timing: settingsViewModel.reminderTiming
        )
        await NotificationService.shared.syncWeeklyDigestReminder(
            schedule: settingsViewModel.weeklyDigestSchedule,
            notificationsEnabled: settingsViewModel.notificationsEnabled,
            digestNotificationsEnabled: settingsViewModel.weeklyDigestNotificationsEnabled
        )
        await maybeGenerateWeeklyDigest(referenceDate: referenceDate)
    }

    @MainActor
    private func maybeGenerateWeeklyDigest(referenceDate: Date = Date()) async {
        do {
            let result = try weeklyDigestService.generateLatestDigestIfNeeded(
                applications: applications,
                existingDigests: weeklyDigests,
                in: modelContext,
                currentResumeRevisionID: currentResumeRevision?.id,
                matchPreferences: settingsViewModel.jobMatchPreferences,
                schedule: settingsViewModel.weeklyDigestSchedule,
                referenceDate: referenceDate
            )
            guard case .created = result else { return }
        } catch {
            print("Weekly digest generation failed: \(error)")
        }
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    ContentView(settingsViewModel: settingsViewModel)
        .environment(AppLockCoordinator(settingsViewModel: settingsViewModel))
        .modelContainer(
            for: [
                JobApplication.self,
                JobSearchCycle.self,
                SearchGoal.self,
                InterviewLog.self,
                CompanyProfile.self,
                CompanyResearchSnapshot.self,
                CompanyResearchSource.self,
                CompanySalarySnapshot.self,
                Contact.self,
                ApplicationContactLink.self,
                ApplicationActivity.self,
                InterviewDebrief.self,
                RejectionLog.self,
                InterviewQuestionEntry.self,
                InterviewLearningSnapshot.self,
                RejectionLearningSnapshot.self,
                ApplicationTask.self,
                ApplicationChecklistSuggestion.self,
                ApplicationAttachment.self,
                CoverLetterDraft.self,
                JobMatchAssessment.self,
                ATSCompatibilityAssessment.self,
                ATSCompatibilityScanRun.self,
                ResumeMasterRevision.self,
                ResumeJobSnapshot.self,
                AIUsageRecord.self,
                AIModelRate.self,
                WeeklyDigestSnapshot.self,
                WeeklyDigestInsight.self,
                WeeklyDigestActionItem.self
            ],
            inMemory: true
        )
}
