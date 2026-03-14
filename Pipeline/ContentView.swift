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
    @State private var settingsEntryPoint: SettingsEntryPoint = .root
    @State private var searchText = ""
    @State private var pendingNotificationOpenRequest: NotificationOpenRequest?
    @Bindable var settingsViewModel: SettingsViewModel
    @Bindable var onboardingStore: OnboardingStore

    private let weeklyDigestService = WeeklyDigestService()
    private let interviewLearningBuilder = InterviewLearningContextBuilder()

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

    private var applyQueueNotificationToken: String {
        let applicationToken = applications.map { application in
            "\(application.id.uuidString)-\(application.updatedAt.timeIntervalSinceReferenceDate)"
        }.joined(separator: "|")

        return [
            "\(settingsViewModel.notificationsEnabled)",
            "\(settingsViewModel.applyQueueDailyTarget)",
            "\(settingsViewModel.applyQueueNotificationHour)",
            "\(settingsViewModel.applyQueueNotificationMinute)",
            currentResumeRevision?.id.uuidString ?? "none",
            settingsViewModel.jobMatchPreferences.fingerprint,
            applicationToken
        ].joined(separator: "|")
    }

    var body: some View {
        ZStack {
            platformContent
                .blur(radius: onboardingStore.isPresentingIntro ? 4 : 0)
                .allowsHitTesting(!onboardingStore.isPresentingIntro)

            if onboardingStore.isPresentingIntro {
                Color.black.opacity(0.24)
                    .ignoresSafeArea()

                OnboardingFlowView(
                    progress: onboardingProgress,
                    onAction: handleOnboardingAction,
                    onComplete: {
                        onboardingStore.completeIntro()
                    },
                    onSkip: {
                        onboardingStore.skipIntro()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: onboardingStore.isPresentingIntro)
        .onAppear {
            onboardingStore.presentIntroIfNeeded()
        }
        .onChange(of: showingSettings) { _, isShowing in
            if !isShowing {
                settingsEntryPoint = .root
            }
        }
    }

    @ViewBuilder
    private var platformContent: some View {
        #if os(macOS)
        MainView(
            selectedDestination: $selectedDestination,
            selectedApplication: $selectedApplication,
            selectedContact: $selectedContact,
            showingAddApplication: $showingAddApplication,
            showingAddContact: $showingAddContact,
            showingSettings: $showingSettings,
            settingsEntryPoint: $settingsEntryPoint,
            searchText: $searchText,
            settingsViewModel: settingsViewModel,
            onboardingStore: onboardingStore,
            onboardingProgress: onboardingProgress,
            onOnboardingAction: handleOnboardingAction,
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
            await refreshAppState()
        }
        .task(id: applyQueueNotificationToken) {
            await syncApplyQueueReminder()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshAppState()
            }
        }
        #else
        NavigationStack {
            Group {
                switch selectedDestination {
                case .dashboard:
                    DashboardView(
                        settingsViewModel: settingsViewModel,
                        onboardingProgress: onboardingProgress,
                        onOnboardingAction: handleOnboardingAction,
                        onHideOnboardingGuidance: {
                            onboardingStore.muteGuidance()
                        }
                    )
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
                        applications: applications,
                        selectedApplication: $selectedApplication,
                        searchText: $searchText,
                        settingsViewModel: settingsViewModel,
                        currentResumeRevisionID: currentResumeRevision?.id,
                        matchPreferences: settingsViewModel.jobMatchPreferences,
                        highlightApplyQueue: pendingNotificationOpenRequest?.kind == .applyQueue
                    )
                case .integrations:
                    IntegrationsWorkspaceView()
                case .offerComparison:
                    OfferComparisonWorkspaceView(settingsViewModel: settingsViewModel)
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
                    ResumeWorkspaceView(
                        onboardingProgress: onboardingProgress,
                        onOnboardingAction: handleOnboardingAction,
                        onHideOnboardingGuidance: {
                            onboardingStore.muteGuidance()
                        }
                    )
                case .costCenter:
                    CostCenterView()
                case .applications:
                    ApplicationListView(
                        applications: filteredApplications,
                        selectedApplication: $selectedApplication,
                        searchText: $searchText,
                        currentResumeRevisionID: nil,
                        matchPreferences: settingsViewModel.jobMatchPreferences,
                        onboardingProgress: onboardingProgress,
                        onOnboardingAction: handleOnboardingAction,
                        onHideOnboardingGuidance: {
                            onboardingStore.muteGuidance()
                        }
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
                        Button("Integrations") { selectedDestination = .integrations }
                        if applications.filter({ $0.status == .offered }).count >= 2 {
                            Button("Compare Offers") { selectedDestination = .offerComparison }
                        }
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
            AddApplicationView(
                settingsViewModel: settingsViewModel,
                onOpenSettings: {
                    showingAddApplication = false
                    Task {
                        try? await Task.sleep(for: .milliseconds(250))
                        openSettings(.aiProvider)
                    }
                },
                onReplayOnboarding: {
                    onboardingStore.presentIntro(force: true)
                }
            )
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
            settingsSheet
        }
        .task {
            prewarmJSONEditorIfNeeded()
            await configureNotificationRouting()
            await refreshAppState()
        }
        .task(id: applyQueueNotificationToken) {
            await syncApplyQueueReminder()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshAppState()
            }
        }
        #endif
    }

    private var onboardingProgress: OnboardingProgress {
        OnboardingProgress(
            applicationCount: applications.count,
            hasApplication: !applications.isEmpty,
            hasConfiguredAI: AIProvider.allCases.contains { provider in
                settingsViewModel.hasAPIKey(for: provider)
            },
            hasSavedResume: currentResumeRevision != nil,
            guidanceMuted: onboardingStore.guidanceMuted,
            hasCompletedIntro: onboardingStore.hasCompletedIntro
        )
    }

    private var settingsSheet: some View {
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

    private func openSettings(_ entryPoint: SettingsEntryPoint = .root) {
        settingsEntryPoint = entryPoint
        showingSettings = true
    }

    @MainActor
    private func handleOnboardingAction(_ action: OnboardingAction) {
        switch action {
        case .addApplication:
            selectedDestination = .applications(.all)
            showingAddApplication = true
        case .openAISettings:
            openSettings(.aiProvider)
        case .openResumeWorkspace:
            selectedDestination = .resume
        case .openIntegrations:
            selectedDestination = .integrations
            openSettings(.integrations)
        case .openDashboard:
            selectedDestination = .dashboard
        case .replayTour:
            onboardingStore.presentIntro(force: true)
        }
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
        case .interviewPrepBrief:
            selectedDestination = .applications(.all)
            if let applicationID = request.applicationID {
                selectedApplication = applications.first(where: { $0.id == applicationID })
            }
        case .weeklyDigest:
            selectedDestination = .weeklyDigest
            selectedApplication = nil
        case .applyQueue:
            selectedDestination = .upcoming
            selectedApplication = nil
        }

        pendingNotificationOpenRequest = request
    }

    @MainActor
    private func syncNotifications(referenceDate: Date = Date()) async {
        do {
            try SmartFollowUpService.shared.refreshAll(applications: applications, in: modelContext)
        } catch {
            print("Smart follow-up refresh failed: \(error)")
        }
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
    private func refreshAppState(referenceDate: Date = Date()) async {
        await syncNotifications(referenceDate: referenceDate)
        await syncApplyQueueReminder()
        await GoogleCalendarImportCoordinator.shared.restoreSessionIfPossible(in: modelContext)
        await GoogleCalendarImportCoordinator.shared.syncIfNeeded(in: modelContext)
        await maybeGenerateInterviewBriefSnapshots(referenceDate: referenceDate)
        await syncInterviewPrepBriefNotifications()
    }

    @MainActor
    private func syncApplyQueueReminder() async {
        await NotificationService.shared.syncApplyQueueReminder(
            applications: applications,
            notificationsEnabled: settingsViewModel.notificationsEnabled,
            dailyTarget: settingsViewModel.applyQueueDailyTarget,
            hour: settingsViewModel.applyQueueNotificationHour,
            minute: settingsViewModel.applyQueueNotificationMinute,
            currentResumeRevisionID: currentResumeRevision?.id,
            matchPreferences: settingsViewModel.jobMatchPreferences
        )
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

    @MainActor
    private func maybeGenerateInterviewBriefSnapshots(referenceDate: Date = Date()) async {
        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)
        let allApplications = applications
        let upcomingActivities = allApplications.flatMap { application in
            application.sortedInterviewActivities.filter { activity in
                activity.occurredAt > referenceDate &&
                activity.occurredAt <= referenceDate.addingTimeInterval(48 * 60 * 60)
            }.map { (application, $0) }
        }

        guard !upcomingActivities.isEmpty else { return }

        let existingSnapshots = fetchInterviewBriefSnapshots()
        let snapshotsByActivityID = Dictionary(uniqueKeysWithValues: existingSnapshots.map { ($0.activityID, $0) })

        for (application, activity) in upcomingActivities {
            let existingSnapshot = snapshotsByActivityID[activity.id]
            guard needsInterviewBriefRefresh(snapshot: existingSnapshot, for: activity, referenceDate: referenceDate) else {
                continue
            }

            let personalizedContext = interviewLearningBuilder.personalizedPrepContext(
                for: application,
                in: allApplications
            )
            let notes = interviewNotesContext(for: application)

            let content: InterviewBriefSnapshotContent
            if !model.isEmpty {
                do {
                    content = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                        try await InterviewBriefSnapshotService.generateSnapshot(
                            provider: provider,
                            apiKey: apiKey,
                            model: model,
                            application: application,
                            activity: activity,
                            notes: notes,
                            personalQuestionBankContext: personalizedContext.boostedQuestions.map(\.question).joined(separator: "\n"),
                            learningSummary: personalizedContext.learningSummary
                        )
                    }
                } catch {
                    content = InterviewBriefSnapshotService.fallbackSnapshot(
                        application: application,
                        activity: activity
                    )
                }
            } else {
                content = InterviewBriefSnapshotService.fallbackSnapshot(
                    application: application,
                    activity: activity
                )
            }

            upsertInterviewBriefSnapshot(
                existingSnapshot,
                applicationID: application.id,
                activityID: activity.id,
                interviewDate: activity.occurredAt,
                content: content
            )
        }

        try? modelContext.save()
    }

    @MainActor
    private func syncInterviewPrepBriefNotifications() async {
        let snapshotsByActivityID = Dictionary(uniqueKeysWithValues: fetchInterviewBriefSnapshots().map { ($0.activityID, $0) })

        for application in applications {
            for activity in application.sortedInterviewActivities where activity.occurredAt > Date() {
                await NotificationService.shared.scheduleInterviewPrepBriefReminder(
                    for: activity.id,
                    applicationID: application.id,
                    companyName: application.companyName,
                    role: application.role,
                    interviewDate: activity.occurredAt,
                    snapshot: snapshotsByActivityID[activity.id]
                )
            }
        }
    }

    private func fetchInterviewBriefSnapshots() -> [InterviewBriefSnapshot] {
        let descriptor = FetchDescriptor<InterviewBriefSnapshot>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func needsInterviewBriefRefresh(
        snapshot: InterviewBriefSnapshot?,
        for activity: ApplicationActivity,
        referenceDate: Date
    ) -> Bool {
        guard let snapshot else { return true }
        if snapshot.isStale {
            return true
        }
        if snapshot.interviewDate != activity.occurredAt {
            return true
        }
        if snapshot.updatedAt < activity.updatedAt {
            return true
        }
        return referenceDate.timeIntervalSince(snapshot.generatedAt) > 12 * 60 * 60
    }

    private func interviewNotesContext(for application: JobApplication) -> String {
        var sections: [String] = []

        if let overview = application.overviewMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !overview.isEmpty {
            sections.append("Overview Notes:\n\(overview)")
        }

        let activityNotes = application.sortedActivities
            .compactMap { activity -> String? in
                switch activity.kind {
                case .email:
                    return activity.emailBodySnapshot ?? activity.notes
                default:
                    return activity.notes
                }
            }
            .joined(separator: "\n")

        if !activityNotes.isEmpty {
            sections.append("Activity Notes:\n\(activityNotes)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func upsertInterviewBriefSnapshot(
        _ snapshot: InterviewBriefSnapshot?,
        applicationID: UUID,
        activityID: UUID,
        interviewDate: Date,
        content: InterviewBriefSnapshotContent
    ) {
        let resolvedSnapshot = snapshot ?? InterviewBriefSnapshot(
            applicationID: applicationID,
            activityID: activityID,
            interviewDate: interviewDate,
            prepDeepLink: content.prepDeepLink
        )

        if resolvedSnapshot.modelContext == nil {
            modelContext.insert(resolvedSnapshot)
        }

        resolvedSnapshot.applicationID = applicationID
        resolvedSnapshot.activityID = activityID
        resolvedSnapshot.interviewDate = interviewDate
        resolvedSnapshot.talkingPoints = content.talkingPoints
        resolvedSnapshot.interviewerHighlights = content.interviewerHighlights
        resolvedSnapshot.mustAskQuestions = content.mustAskQuestions
        resolvedSnapshot.companyResearchSummary = content.companyResearchSummary
        resolvedSnapshot.prepDeepLink = content.prepDeepLink
        resolvedSnapshot.generatedAt = content.generatedAt
        resolvedSnapshot.isStale = false
        resolvedSnapshot.updateTimestamp()
    }
}

#Preview {
    let settingsViewModel = SettingsViewModel()
    ContentView(
        settingsViewModel: settingsViewModel,
        onboardingStore: OnboardingStore()
    )
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
                FollowUpStep.self,
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
                WeeklyDigestActionItem.self,
                GoogleCalendarAccount.self,
                GoogleCalendarSubscription.self,
                GoogleCalendarImportRecord.self,
                GoogleCalendarInterviewLink.self,
                InterviewBriefSnapshot.self
            ],
            inMemory: true
        )
}
