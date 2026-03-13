import SwiftUI
import SwiftData
import PipelineKit

private enum CompanyWorkspaceTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case research = "Research"
    case salary = "Salary"

    var id: String { rawValue }
}

struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allApplications: [JobApplication]
    @Query(sort: \InterviewLearningSnapshot.generatedAt, order: .reverse)
    private var interviewLearningSnapshots: [InterviewLearningSnapshot]
    @Query(sort: \RejectionLearningSnapshot.generatedAt, order: .reverse)
    private var rejectionLearningSnapshots: [RejectionLearningSnapshot]
    @Bindable var application: JobApplication
    var onClose: (() -> Void)? = nil
    var onSelectContact: ((Contact) -> Void)? = nil
    var pendingNotificationOpenRequest: NotificationOpenRequest? = nil
    var onHandledNotificationOpenRequest: (() -> Void)? = nil

    @State private var viewModel = ApplicationDetailViewModel()
    @State private var showingEditSheet = false
    @State private var showingManageContacts = false
    @State private var showingActivityEditor = false
    @State private var draftActivityKind: ApplicationActivityKind = .note
    @State private var editingActivity: ApplicationActivity?
    @State private var showingTaskEditor = false
    @State private var editingTask: ApplicationTask?
    @State private var showingDeleteAlert = false
    @State private var showingInterviewPrep = false
    @State private var showingInterviewLearnings = false
    @State private var selectedRejectionActivityForLog: ApplicationActivity?
    @State private var showingFollowUpDrafter = false
    @State private var showingCoverLetterEditor = false
    @State private var showingTailorResume = false
    @State private var resumeTailoringMode: ResumeTailoringMode = .standard
    @State private var resumeSeededPatches: [ResumePatch] = []
    @State private var showingCompanyWorkspace = false
    @State private var companyWorkspaceTab: CompanyWorkspaceTab = .overview
    @State private var actionErrorMessage: String?
    @State private var descriptionDenoiseViewModel: JobDescriptionDenoiseViewModel
    @State private var checklistSuggestionsViewModel: ChecklistSuggestionsViewModel
    @State private var selectedInterviewActivityForDebrief: ApplicationActivity?
    @State private var rejectionLearningsViewModel: RejectionLearningsViewModel?
    @Environment(\.colorScheme) private var colorScheme

    init(
        application: JobApplication,
        onClose: (() -> Void)? = nil,
        onSelectContact: ((Contact) -> Void)? = nil,
        pendingNotificationOpenRequest: NotificationOpenRequest? = nil,
        onHandledNotificationOpenRequest: (() -> Void)? = nil
    ) {
        self.application = application
        self.onClose = onClose
        self.onSelectContact = onSelectContact
        self.pendingNotificationOpenRequest = pendingNotificationOpenRequest
        self.onHandledNotificationOpenRequest = onHandledNotificationOpenRequest
        _descriptionDenoiseViewModel = State(
            initialValue: JobDescriptionDenoiseViewModel(
                application: application,
                settingsViewModel: SettingsViewModel()
            )
        )
        _checklistSuggestionsViewModel = State(
            initialValue: ChecklistSuggestionsViewModel(
                application: application,
                settingsViewModel: SettingsViewModel()
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            JobDetailHeaderView(
                application: application,
                onClose: onClose,
                onDelete: { showingDeleteAlert = true },
                onStatusChange: { status in
                    do {
                        let result = try viewModel.updateStatus(status, for: application, context: modelContext)
                        if result.needsRejectionLogPrompt, let activityID = result.statusActivityID {
                            selectedRejectionActivityForLog = application.sortedActivities.first(where: { $0.id == activityID })
                        }
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                },
                onPriorityChange: { priority in
                    do {
                        try viewModel.updatePriority(priority, for: application, context: modelContext)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                }
            )
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    JobDetailFieldsView(application: application)

                    ApplicationCompanySection(
                        application: application,
                        onOpenWorkspace: { tab in
                            openCompanyWorkspace(tab)
                        }
                    )

                    if let urlString = application.jobURL, !urlString.isEmpty {
                        JobPostingSection(urlString: urlString)
                    }

                    if application.status == .interviewing {
                        InterviewStageIndicator(
                            currentStage: application.interviewStage,
                            onStageChange: { newStage in
                                do {
                                    try viewModel.updateInterviewStage(newStage, for: application, context: modelContext)
                                } catch {
                                    actionErrorMessage = error.localizedDescription
                                }
                            }
                        )
                        .padding(.horizontal, 6)
                    }

                    if let description = application.jobDescription, !description.isEmpty {
                        JobDescriptionView(
                            description: description,
                            isDenoising: descriptionDenoiseViewModel.isLoading,
                            onDenoise: {
                                Task {
                                    await descriptionDenoiseViewModel.generateProposal()
                                }
                            }
                        )
                    }

                    JobMatchSection(
                        application: application,
                        settingsViewModel: SettingsViewModel(),
                        onRefresh: {
                            Task {
                                await JobMatchScoringCoordinator.shared.refresh(
                                    application: application,
                                    modelContext: modelContext,
                                    settingsViewModel: SettingsViewModel(),
                                    force: true
                                )
                            }
                        }
                    )

                    ATSCompatibilitySection(
                        application: application,
                        onGenerateFixes: { assessment in
                            resumeSeededPatches = []
                            resumeTailoringMode = .atsFixes(ATSFixContext(assessment: assessment))
                            showingTailorResume = true
                        },
                        onGenerateQuickFixes: { assessment in
                            openATSQuickFixes(for: assessment)
                        }
                    )

                    ApplicationContactsSection(
                        application: application,
                        onManageContacts: {
                            showingManageContacts = true
                        },
                        onSelectContact: onSelectContact
                    )

                    JobResumePanel(application: application)

                    ApplicationOverviewNotesSection(
                        application: application,
                        viewModel: viewModel
                    )

                    if application.status == .rejected || application.latestRejectionLog != nil {
                        RejectionAnalysisSection(
                            application: application,
                            latestSnapshot: rejectionLearningSnapshots.first,
                            recoverySuggestions: RejectionRecoveryService.suggestions(
                                for: application,
                                among: allApplications
                            ),
                            hasConfiguredAI: rejectionLearningsViewModel?.hasConfiguredAI ?? false,
                            isAnalyzing: rejectionLearningsViewModel?.isAnalyzing ?? false,
                            onFillLog: {
                                if let latestRejectionActivity = application.latestRejectionActivity {
                                    selectedRejectionActivityForLog = latestRejectionActivity
                                }
                            },
                            onAnalyze: {
                                Task {
                                    await rejectionLearningsViewModel?.refresh()
                                    if let error = rejectionLearningsViewModel?.error {
                                        actionErrorMessage = error
                                        rejectionLearningsViewModel?.error = nil
                                    }
                                }
                            }
                        )
                    }

                    if !application.sortedInterviewActivities.isEmpty {
                        InterviewLearningsSection(
                            application: application,
                            applications: allApplications,
                            latestSnapshot: interviewLearningSnapshots.first,
                            onDebriefLatest: {
                                if let latestInterviewNeedingDebrief {
                                    openDebrief(for: latestInterviewNeedingDebrief)
                                } else if let latestInterviewActivity {
                                    openDebrief(for: latestInterviewActivity)
                                }
                            },
                            onViewLearnings: {
                                showingInterviewLearnings = true
                            }
                        )
                    }

                    ApplicationChecklistSection(
                        application: application,
                        viewModel: viewModel,
                        onEditTask: { task in
                            editingTask = task
                        },
                        onOpenTaskAction: { task in
                            openChecklistAction(for: task)
                        },
                        onError: { message in
                            actionErrorMessage = message
                        }
                    )

                    ApplicationChecklistSuggestionsSection(
                        viewModel: checklistSuggestionsViewModel
                    )

                    ApplicationTasksSection(
                        application: application,
                        viewModel: viewModel,
                        onAddTask: {
                            showingTaskEditor = true
                        },
                        onEditTask: { task in
                            editingTask = task
                        },
                        onError: { message in
                            actionErrorMessage = message
                        }
                    )

                    ApplicationTimelineView(
                        activities: application.sortedActivities,
                        onAddActivity: { kind in
                            draftActivityKind = kind
                            showingActivityEditor = true
                        },
                        onEditActivity: { activity in
                            editingActivity = activity
                        },
                        onDeleteActivity: { activity in
                            do {
                                try viewModel.deleteActivity(activity, from: application, context: modelContext)
                            } catch {
                                actionErrorMessage = error.localizedDescription
                            }
                        },
                        onDebrief: { activity in
                            openDebrief(for: activity)
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))
            bottomActionBar
        }
        .navigationTitle("")
        .sheet(isPresented: $showingEditSheet) {
            EditApplicationView(application: application)
        }
        .sheet(isPresented: $showingManageContacts) {
            ManageApplicationContactsView(application: application)
        }
        .sheet(isPresented: $showingActivityEditor) {
            ActivityEditorView(
                application: application,
                defaultKind: draftActivityKind
            )
        }
        .sheet(item: $editingActivity) { activity in
            ActivityEditorView(application: application, activityToEdit: activity)
        }
        .sheet(isPresented: $showingTaskEditor) {
            ApplicationTaskEditorView(application: application)
        }
        .sheet(item: $editingTask) { task in
            ApplicationTaskEditorView(application: application, taskToEdit: task)
        }
        .sheet(isPresented: $showingTailorResume) {
            ResumeTailoringView(
                application: application,
                mode: resumeTailoringMode,
                seededPatches: resumeSeededPatches
            )
        }
        .sheet(isPresented: $showingInterviewPrep) {
            InterviewPrepView(
                viewModel: InterviewPrepViewModel(
                    application: application,
                    settingsViewModel: SettingsViewModel(),
                    modelContext: modelContext
                )
            )
        }
        .sheet(item: $selectedInterviewActivityForDebrief) { activity in
            InterviewDebriefSheet(
                viewModel: InterviewDebriefViewModel(
                    activity: activity,
                    application: application,
                    modelContext: modelContext
                )
            )
        }
        .sheet(item: $selectedRejectionActivityForLog) { activity in
            RejectionLogSheet(
                viewModel: RejectionLogEditorViewModel(
                    activity: activity,
                    application: application,
                    modelContext: modelContext,
                    settingsViewModel: SettingsViewModel()
                ),
                onSaved: {
                    rejectionLearningsViewModel?.load()
                }
            )
        }
        .sheet(isPresented: $showingInterviewLearnings) {
            InterviewLearningsView(
                viewModel: InterviewLearningsViewModel(
                    settingsViewModel: SettingsViewModel(),
                    modelContext: modelContext
                )
            )
        }
        .sheet(isPresented: $showingFollowUpDrafter) {
            FollowUpDrafterView(
                viewModel: FollowUpDrafterViewModel(
                    application: application,
                    settingsViewModel: SettingsViewModel(),
                    modelContext: modelContext
                )
            )
        }
        .sheet(isPresented: $showingCoverLetterEditor) {
            CoverLetterEditorView(
                viewModel: CoverLetterEditorViewModel(
                    application: application,
                    settingsViewModel: SettingsViewModel(),
                    modelContext: modelContext
                )
            )
        }
        .sheet(isPresented: $showingCompanyWorkspace) {
            if let company = application.company {
                CompanyWorkspaceView(
                    application: application,
                    company: company,
                    initialTab: companyWorkspaceTab,
                    detailViewModel: viewModel,
                    settingsViewModel: SettingsViewModel()
                )
            } else {
                ContentUnavailableView(
                    "Company unavailable",
                    systemImage: "building.2",
                    description: Text("Pipeline could not load the shared company profile for this application.")
                )
                .padding()
            }
        }
        .sheet(
            isPresented: Binding(
                get: { descriptionDenoiseViewModel.isShowingReview },
                set: { isPresented in
                    if !isPresented {
                        descriptionDenoiseViewModel.dismissReview()
                    }
                }
            )
        ) {
            JobDescriptionDenoiseReviewSheet(
                originalDescription: descriptionDenoiseViewModel.originalDescription ?? "",
                cleanedDescription: descriptionDenoiseViewModel.cleanedDescription ?? "",
                onCancel: {
                    descriptionDenoiseViewModel.dismissReview()
                },
                onReplace: {
                    descriptionDenoiseViewModel.applyReplacement()
                }
            )
        }
        .alert("Delete Application", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                do {
                    try viewModel.delete(application, context: modelContext)
                    onClose?()
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("Are you sure you want to delete this application? This action cannot be undone.")
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: descriptionDenoiseViewModel.error) { _, newValue in
            guard let newValue else { return }
            actionErrorMessage = newValue
            descriptionDenoiseViewModel.clearError()
        }
        .onChange(of: checklistSuggestionsViewModel.error) { _, newValue in
            guard let newValue else { return }
            actionErrorMessage = newValue
            checklistSuggestionsViewModel.clearError()
        }
        .task(id: application.id) {
            rejectionLearningsViewModel = RejectionLearningsViewModel(
                settingsViewModel: SettingsViewModel(),
                modelContext: modelContext
            )
            rejectionLearningsViewModel?.load()
            descriptionDenoiseViewModel.setModelContext(modelContext)
            checklistSuggestionsViewModel.setModelContext(modelContext)
            if application.company == nil {
                do {
                    _ = try viewModel.ensureCompanyProfile(for: application, context: modelContext)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }

            do {
                try ApplicationChecklistService().sync(for: application, trigger: .detailViewed, in: modelContext)
                Task { @MainActor in
                    await NotificationService.shared.syncReminderState(for: application)
                }
            } catch {
                actionErrorMessage = error.localizedDescription
            }
            handlePendingOpenRequestIfNeeded()
        }
        .onChange(of: pendingNotificationOpenRequest) { _, _ in
            handlePendingOpenRequestIfNeeded()
        }
    }

    private func openCompanyWorkspace(_ tab: CompanyWorkspaceTab) {
        do {
            _ = try viewModel.ensureCompanyProfile(for: application, context: modelContext)
            companyWorkspaceTab = tab
            showingCompanyWorkspace = true
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private func openChecklistAction(for task: ApplicationTask) {
        switch task.actionKind {
        case .none:
            break
        case .resumeTailoring:
            resumeSeededPatches = []
            resumeTailoringMode = .standard
            showingTailorResume = true
        case .coverLetter:
            showingCoverLetterEditor = true
        case .companyResearch:
            openCompanyWorkspace(.research)
        case .manageContacts:
            showingManageContacts = true
        case .interviewPrep:
            showingInterviewPrep = true
        case .followUpDrafter:
            showingFollowUpDrafter = true
        case .salaryComparison:
            openCompanyWorkspace(.salary)
        }
    }

    private func openATSQuickFixes(for assessment: ATSCompatibilityAssessment) {
        do {
            guard let masterRevision = try ResumeStoreService.currentMasterRevision(
                in: modelContext
            ) else {
                actionErrorMessage = ATSBlockedReason.missingResumeSource.message
                return
            }

            let result = try ATSCompatibilityQuickFixService.makeSkillPromotionPatches(
                assessment: assessment,
                resumeJSON: masterRevision.rawJSON
            )

            guard !result.patches.isEmpty else {
                actionErrorMessage = "No deterministic ATS quick fixes are available for this resume yet."
                return
            }

            resumeSeededPatches = result.patches
            resumeTailoringMode = .atsQuickFixes(
                ATSQuickFixContext(
                    assessment: assessment,
                    unsupportedKeywords: result.unsupportedKeywords
                )
            )
            showingTailorResume = true
        } catch {
            actionErrorMessage = error.localizedDescription
        }
    }

    private var latestInterviewActivity: ApplicationActivity? {
        application.sortedInterviewActivities.first
    }

    private var latestInterviewNeedingDebrief: ApplicationActivity? {
        application.pendingInterviewDebriefs.first
    }

    private func openDebrief(for activity: ApplicationActivity) {
        selectedInterviewActivityForDebrief = activity
    }

    private func handlePendingOpenRequestIfNeeded() {
        guard let pendingNotificationOpenRequest,
              pendingNotificationOpenRequest.applicationID == application.id,
              pendingNotificationOpenRequest.kind == .interviewDebrief else {
            return
        }

        if let activityID = pendingNotificationOpenRequest.interviewActivityID,
           let activity = application.sortedInterviewActivities.first(where: { $0.id == activityID }) {
            selectedInterviewActivityForDebrief = activity
        } else if let latestInterviewNeedingDebrief {
            selectedInterviewActivityForDebrief = latestInterviewNeedingDebrief
        }

        onHandledNotificationOpenRequest?()
    }

    private var bottomActionBar: some View {
        HStack(spacing: 12) {
            Button {
                showingEditSheet = true
            } label: {
                Label("Edit", systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)

            Menu {
                ForEach(ApplicationActivityKind.manualCases) { kind in
                    Button {
                        draftActivityKind = kind
                        showingActivityEditor = true
                    } label: {
                        Label(kind.displayName, systemImage: kind.icon)
                    }
                }
            } label: {
                Label("Log", systemImage: "plus")
                    .frame(width: 110)
            }
            .buttonStyle(.bordered)

            Menu {
                if application.status == .interviewing {
                    if let latestInterviewNeedingDebrief {
                        Button {
                            openDebrief(for: latestInterviewNeedingDebrief)
                        } label: {
                            Label("Debrief Latest", systemImage: "square.and.pencil")
                        }
                    }

                    Button {
                        showingInterviewPrep = true
                    } label: {
                        Label("Interview Prep", systemImage: "sparkles")
                    }
                }

                if !application.sortedInterviewActivities.isEmpty {
                    Button {
                        showingInterviewLearnings = true
                    } label: {
                        Label("Interview Learnings", systemImage: "brain")
                    }
                }

                Button {
                    showingFollowUpDrafter = true
                } label: {
                    Label("Follow Up", systemImage: "envelope.badge")
                }

                Button {
                    showingCoverLetterEditor = true
                } label: {
                    Label("Cover Letter", systemImage: "doc.text")
                }
            } label: {
                Label("AI", systemImage: "sparkles")
                    .frame(width: 120)
            }
            .buttonStyle(.bordered)

            if application.status != .archived {
                Button {
                    do {
                        try viewModel.archive(application, context: modelContext)
                    } catch {
                        actionErrorMessage = error.localizedDescription
                    }
                } label: {
                    Label("Archive", systemImage: "archivebox")
                        .frame(width: 120)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
}

private struct ApplicationCompanySection: View {
    @Environment(\.openURL) private var openURL
    @Bindable var application: JobApplication
    let onOpenWorkspace: (CompanyWorkspaceTab) -> Void

    private var company: CompanyProfile? {
        application.company
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) {
                    Label("Company", systemImage: "building.2")
                        .font(.headline)

                    Spacer()

                    actionButtons
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Company", systemImage: "building.2")
                        .font(.headline)

                    actionButtons
                }
            }

            if let company {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        if let rating = company.userRating {
                            HStack(spacing: 6) {
                                StarRatingDisplay(rating: rating, size: 12)
                                Text("\(rating)/5")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        capsuleLabel("\(company.sortedApplications.count) application\(company.sortedApplications.count == 1 ? "" : "s")")

                        if let industry = company.industry {
                            capsuleLabel(industry)
                        }

                        if let sizeBand = company.sizeBand {
                            capsuleLabel(sizeBand.title)
                        }
                    }

                    if let summary = preferredSummary(company) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(4)
                    } else {
                        Text("No company summary yet. Run Research to gather a reusable company overview, source links, and salary signals.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 16) {
                        if let headquarters = company.headquarters {
                            Label(headquarters, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let websiteURL = company.websiteURL,
                           let domain = URLHelpers.extractDomain(from: websiteURL) {
                            Label(domain, systemImage: "globe")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let lastResearchedAt = company.lastResearchedAt {
                            Label(lastResearchedAt.formatted(date: .abbreviated, time: .omitted), systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No shared company profile yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Pipeline will create one automatically so notes, ratings, research, and salary comparisons can be reused across multiple applications at the same company.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
    }

    private func preferredSummary(_ company: CompanyProfile) -> String? {
        if let summary = company.lastResearchSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return summary
        }

        if let notes = company.notesMarkdown?.trimmingCharacters(in: .whitespacesAndNewlines),
           !notes.isEmpty {
            return notes
        }

        return nil
    }

    private func openSources() {
        if let url = company?.sortedResearchSources.first?.normalizedURL {
            openURL(url)
            return
        }

        if let link = company?.sourceLinks.first,
           let url = URL(string: link) {
            openURL(url)
            return
        }

        onOpenWorkspace(.research)
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            Button {
                onOpenWorkspace(.overview)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                onOpenWorkspace(.research)
            } label: {
                Label("Research", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.small)

            Button {
                openSources()
            } label: {
                Label("Open Sources", systemImage: "arrow.up.right.square")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .labelStyle(.titleAndIcon)
    }

    private func capsuleLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct CompanyProfileDraft {
    var name: String
    var websiteURL: String
    var linkedInURL: String
    var glassdoorURL: String
    var levelsFYIURL: String
    var teamBlindURL: String
    var industry: String
    var headquarters: String
    var notesMarkdown: String
    var hasRating: Bool
    var rating: Int
    var sizeBand: CompanySizeBand?

    init(company: CompanyProfile) {
        name = company.name
        websiteURL = company.websiteURL ?? ""
        linkedInURL = company.linkedInURL ?? ""
        glassdoorURL = company.glassdoorURL ?? ""
        levelsFYIURL = company.levelsFYIURL ?? ""
        teamBlindURL = company.teamBlindURL ?? ""
        industry = company.industry ?? ""
        headquarters = company.headquarters ?? ""
        notesMarkdown = company.notesMarkdown ?? ""
        hasRating = company.userRating != nil
        rating = max(company.userRating ?? 3, 1)
        sizeBand = company.sizeBand
    }

    var userRating: Int? {
        hasRating ? rating : nil
    }
}

private struct CompanyWorkspaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    let application: JobApplication
    @Bindable var company: CompanyProfile
    let detailViewModel: ApplicationDetailViewModel
    let settingsViewModel: SettingsViewModel

    @State private var selectedTab: CompanyWorkspaceTab
    @State private var draft: CompanyProfileDraft
    @State private var researchViewModel: CompanyResearchViewModel
    @State private var showingSalaryEditor = false
    @State private var editingSalarySnapshot: CompanySalarySnapshot?
    @State private var saveErrorMessage: String?

    init(
        application: JobApplication,
        company: CompanyProfile,
        initialTab: CompanyWorkspaceTab,
        detailViewModel: ApplicationDetailViewModel,
        settingsViewModel: SettingsViewModel
    ) {
        self.application = application
        self.company = company
        self.detailViewModel = detailViewModel
        self.settingsViewModel = settingsViewModel
        _selectedTab = State(initialValue: initialTab)
        _draft = State(initialValue: CompanyProfileDraft(company: company))
        _researchViewModel = State(initialValue: CompanyResearchViewModel(
            application: application,
            company: company,
            settingsViewModel: settingsViewModel,
            modelContext: nil
        ))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("Company Tab", selection: $selectedTab) {
                        ForEach(CompanyWorkspaceTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)

                    switch selectedTab {
                    case .overview:
                        overviewTab
                    case .research:
                        researchTab
                    case .salary:
                        salaryTab
                    }
                }
                .padding(20)
            }
            .navigationTitle(company.name)
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 860, minHeight: 640, idealHeight: 760)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button("Save") {
                        saveProfile()
                    }
                    .disabled(selectedTab != .overview)
                }
            }
        }
        .sheet(isPresented: $showingSalaryEditor, onDismiss: {
            Task {
                await researchViewModel.refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
            }
        }) {
            CompanySalarySnapshotEditorView(
                company: company,
                detailViewModel: detailViewModel,
                snapshot: editingSalarySnapshot
            )
        }
        .task {
            researchViewModel = CompanyResearchViewModel(
                application: application,
                company: company,
                settingsViewModel: settingsViewModel,
                modelContext: modelContext
            )
            await researchViewModel.refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
        }
        .task(id: settingsViewModel.analyticsBaseCurrency.rawValue) {
            await researchViewModel.refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
        }
        .alert("Company Workspace Error", isPresented: Binding(
            get: { saveErrorMessage != nil || researchViewModel.error != nil },
            set: { if !$0 { saveErrorMessage = nil; researchViewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? researchViewModel.error ?? "Unknown error")
        }
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            companyCard(title: "Company Profile", subtitle: "Manual edits are authoritative. AI only fills in gaps.") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Company Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)

                    TextField("Website", text: $draft.websiteURL)
                        .textFieldStyle(.roundedBorder)

                    TextField("Industry", text: $draft.industry)
                        .textFieldStyle(.roundedBorder)

                    Picker("Size", selection: Binding(
                        get: { draft.sizeBand },
                        set: { draft.sizeBand = $0 }
                    )) {
                        Text("Unknown").tag(CompanySizeBand?.none)
                        ForEach(CompanySizeBand.allCases) { band in
                            Text(band.title).tag(CompanySizeBand?.some(band))
                        }
                    }
                    .pickerStyle(.menu)

                    TextField("Headquarters", text: $draft.headquarters)
                        .textFieldStyle(.roundedBorder)

                    Toggle("Personal Rating", isOn: $draft.hasRating)
                    if draft.hasRating {
                        StarRating(rating: $draft.rating)
                    }
                }
            }

            companyCard(title: "Research Links", subtitle: "Store source URLs you trust. Research runs will reuse them.") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("LinkedIn URL", text: $draft.linkedInURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Glassdoor URL", text: $draft.glassdoorURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("Levels.fyi URL", text: $draft.levelsFYIURL)
                        .textFieldStyle(.roundedBorder)
                    TextField("TeamBlind URL", text: $draft.teamBlindURL)
                        .textFieldStyle(.roundedBorder)
                }
            }

            companyCard(title: "Notes", subtitle: "These stay pinned for the company across applications.") {
                TextEditor(text: $draft.notesMarkdown)
                    .frame(minHeight: 180)
            }

            HStack {
                Spacer()
                Button {
                    saveProfile()
                } label: {
                    Label("Save Company", systemImage: "checkmark.circle")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
        }
    }

    private var researchTab: some View {
        let latestSnapshot = company.sortedResearchSnapshots.first
        let latestSources = latestSnapshot?.sortedSources ?? company.sortedResearchSources

        return VStack(alignment: .leading, spacing: 16) {
            companyCard(
                title: "Research Run",
                subtitle: company.lastResearchedAt.map { "Last refreshed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Run structured AI research against the company profile and saved links."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let latestSnapshot {
                        researchRunBanner(snapshot: latestSnapshot)
                    }

                    if researchViewModel.isLoading {
                        ProgressView("Researching company…")
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await researchViewModel.generateResearch() }
                        } label: {
                            Label(company.lastResearchedAt == nil ? "Run Research" : "Refresh Research", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(DesignSystem.Colors.accent)
                        .disabled(researchViewModel.isLoading)

                        if let lastCompletedAt = researchViewModel.lastCompletedAt {
                            Text("Updated \(lastCompletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            companyCard(title: "Summary", subtitle: "The latest saved company overview.") {
                if let latestSnapshot,
                   let summary = latestSnapshot.summaryText,
                   !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(summary)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)

                        if let confidenceNote = latestSnapshot.summaryConfidenceNote, !confidenceNote.isEmpty {
                            Text(confidenceNote)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No AI research summary yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            companyCard(title: "Sources", subtitle: "Fetched and manual links retained on the company profile.") {
                if latestSources.isEmpty && company.sourceLinks.isEmpty {
                    Text("No sources saved yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(latestSources) { source in
                            sourceRow(source)
                        }

                        ForEach(company.sourceLinks.filter { link in
                            !latestSources.contains(where: { $0.urlString == link || $0.resolvedURLString == link })
                        }, id: \.self) { link in
                            if let url = URL(string: link) {
                                Link(destination: url) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(URLHelpers.displayURL(link))
                                                .font(.subheadline.weight(.medium))
                                            Text("Manual link")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.up.right.square")
                                            .foregroundColor(DesignSystem.Colors.accent)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }

            companyCard(title: "Research History", subtitle: "Recent company research runs.") {
                if company.sortedResearchSnapshots.isEmpty {
                    Text("No research snapshots yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(company.sortedResearchSnapshots.prefix(5)) { snapshot in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(snapshot.finishedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.subheadline.weight(.medium))
                                    Text("\(snapshot.providerID.capitalized) · \(snapshot.model)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 8) {
                                    Text(snapshot.runStatus.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(runStatusColor(snapshot.runStatus))

                                    Button("Delete", role: .destructive) {
                                        deleteResearchSnapshot(snapshot)
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var salaryTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            companyCard(
                title: "Comparison",
                subtitle: "Compares this role against your own same-company applications and external salary snapshots."
            ) {
                if researchViewModel.isRefreshingComparison {
                    ProgressView("Refreshing salary comparison…")
                } else if let comparison = researchViewModel.comparison {
                    VStack(alignment: .leading, spacing: 12) {
                        if let currentRangeText = comparison.currentApplicationRangeText {
                            Label("Current application: \(currentRangeText) \(comparison.baseCurrency.rawValue)", systemImage: "flag")
                                .font(.subheadline)
                        }

                        if !comparison.internalRows.isEmpty {
                            comparisonGroup(title: "Same Company in Pipeline", rows: comparison.internalRows)
                        }

                        if !comparison.externalRows.isEmpty {
                            comparisonGroup(title: "External Research", rows: comparison.externalRows)
                        }

                        if comparison.internalRows.isEmpty && comparison.externalRows.isEmpty {
                            Text("No salary comparisons yet. Add a market snapshot manually or run Research.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if comparison.missingConversionCount > 0 {
                            Text("\(comparison.missingConversionCount) row(s) could not be converted into \(comparison.baseCurrency.rawValue).")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } else {
                    Text("No salary comparison available yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            companyCard(title: "Market Snapshots", subtitle: "Editable salary data stored against the company profile.") {
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        editingSalarySnapshot = nil
                        showingSalaryEditor = true
                    } label: {
                        Label("Add Snapshot", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)

                    if company.sortedSalarySnapshots.isEmpty {
                        Text("No salary snapshots yet.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(company.sortedSalarySnapshots) { snapshot in
                            salarySnapshotRow(snapshot)
                        }
                    }
                }
            }
        }
    }

    private func researchRunBanner(snapshot: CompanyResearchSnapshot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: bannerIcon(for: snapshot.runStatus))
                .foregroundColor(runStatusColor(snapshot.runStatus))

            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.runStatus.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(runStatusColor(snapshot.runStatus))

                Text(snapshot.errorMessage ?? snapshot.summaryConfidenceNote ?? "Research completed without additional notes.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func companyCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            content()
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func sourceRow(_ source: CompanyResearchSource) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.title)
                        .font(.subheadline.weight(.medium))
                    Text("\(source.sourceKind.title) · \(source.acquisitionMethod.title)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let reason = source.validationReason, !reason.isEmpty {
                        Text(reason)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    if let excerpt = source.contentExcerpt, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                    if let errorMessage = source.errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 8) {
                    Text(source.validationStatus.title)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(statusBackgroundColor(for: source.validationStatus))
                        )
                        .foregroundColor(statusForegroundColor(for: source.validationStatus))

                    if let confidence = source.confidence {
                        Text(confidence.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            ViewThatFits(in: .vertical) {
                HStack(spacing: 8) {
                    sourceActionButtons(source)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    sourceActionButtons(source)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    @ViewBuilder
    private func sourceActionButtons(_ source: CompanyResearchSource) -> some View {
        Button("Retry") {
            Task { await researchViewModel.retryResearch(for: source) }
        }
        .buttonStyle(.bordered)

        if let url = source.resolvedURL ?? source.normalizedURL {
            Button("Open") {
                openURL(url)
            }
            .buttonStyle(.bordered)
        }

        Button(source.isExcludedFromResearch ? "Include" : "Exclude") {
            researchViewModel.setExcluded(!source.isExcludedFromResearch, for: source)
        }
        .buttonStyle(.bordered)

        Button("Delete", role: .destructive) {
            deleteResearchSource(source)
        }
        .buttonStyle(.bordered)

        if source.sourceKind != .manual &&
            (source.validationStatus == .blocked || source.validationStatus == .invalid) {
            Button("Use Manual Note") {
                researchViewModel.useManualNote(for: source)
            }
            .buttonStyle(.bordered)
        }
    }

    private func bannerIcon(for runStatus: ResearchRunStatus) -> String {
        switch runStatus {
        case .succeeded:
            return "checkmark.seal.fill"
        case .partial:
            return "exclamationmark.triangle.fill"
        case .failed:
            return "xmark.octagon.fill"
        }
    }

    private func runStatusColor(_ runStatus: ResearchRunStatus) -> Color {
        switch runStatus {
        case .succeeded:
            return .green
        case .partial:
            return .orange
        case .failed:
            return .red
        }
    }

    private func statusForegroundColor(for status: ResearchValidationStatus) -> Color {
        switch status {
        case .verified, .manual:
            return .green
        case .partial:
            return .orange
        case .blocked, .invalid:
            return .red
        case .skipped:
            return .secondary
        }
    }

    private func statusBackgroundColor(for status: ResearchValidationStatus) -> Color {
        switch status {
        case .verified, .manual:
            return Color.green.opacity(0.12)
        case .partial:
            return Color.orange.opacity(0.14)
        case .blocked, .invalid:
            return Color.red.opacity(0.12)
        case .skipped:
            return Color.secondary.opacity(0.12)
        }
    }

    private func comparisonGroup(title: String, rows: [CompanyCompensationComparisonRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.label)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(row.rangeText)
                            .font(.subheadline.weight(.semibold))
                    }
                    Text(row.sourceLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let secondaryText = row.secondaryText {
                        Text(secondaryText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                )
            }
        }
    }

    private func salarySnapshotRow(_ snapshot: CompanySalarySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(snapshot.roleTitle) · \(snapshot.location)")
                        .font(.subheadline.weight(.semibold))
                    Text(snapshot.sourceName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let totalRange = snapshot.totalRangeText ?? snapshot.baseRangeText {
                        Text(totalRange)
                            .font(.subheadline.weight(.semibold))
                    }
                    HStack(spacing: 10) {
                        Button("Edit") {
                            editingSalarySnapshot = snapshot
                            showingSalaryEditor = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.accent)

                        Button("Delete", role: .destructive) {
                            deleteSalarySnapshot(snapshot)
                        }
                        .buttonStyle(.plain)
                    }
                    .font(.caption)
                }
            }

            if let confidenceNotes = snapshot.confidenceNotes {
                Text(confidenceNotes)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let sourceURLString = snapshot.sourceURLString,
               let url = URL(string: sourceURLString) {
                Button {
                    openURL(url)
                } label: {
                    Label(URLHelpers.displayURL(sourceURLString), systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(DesignSystem.Colors.accent)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func saveProfile() {
        do {
            try detailViewModel.saveCompanyProfile(
                company,
                name: draft.name,
                websiteURL: normalized(draft.websiteURL),
                linkedInURL: normalized(draft.linkedInURL),
                glassdoorURL: normalized(draft.glassdoorURL),
                levelsFYIURL: normalized(draft.levelsFYIURL),
                teamBlindURL: normalized(draft.teamBlindURL),
                industry: normalized(draft.industry),
                sizeBand: draft.sizeBand,
                headquarters: normalized(draft.headquarters),
                userRating: draft.userRating,
                notesMarkdown: normalized(draft.notesMarkdown),
                context: modelContext
            )
            draft = CompanyProfileDraft(company: company)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteSalarySnapshot(_ snapshot: CompanySalarySnapshot) {
        do {
            try detailViewModel.deleteCompanySalarySnapshot(snapshot, context: modelContext)
            Task {
                await researchViewModel.refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteResearchSource(_ source: CompanyResearchSource) {
        do {
            try detailViewModel.deleteCompanyResearchSource(source, context: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func deleteResearchSnapshot(_ snapshot: CompanyResearchSnapshot) {
        do {
            try detailViewModel.deleteCompanyResearchSnapshot(snapshot, context: modelContext)
            Task {
                await researchViewModel.refreshComparison(baseCurrency: settingsViewModel.analyticsBaseCurrency)
            }
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct CompanySalarySnapshotEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let company: CompanyProfile
    let detailViewModel: ApplicationDetailViewModel
    let snapshot: CompanySalarySnapshot?

    @State private var roleTitle: String
    @State private var location: String
    @State private var sourceName: String
    @State private var sourceURLString: String
    @State private var notes: String
    @State private var confidenceNotes: String
    @State private var currency: Currency
    @State private var minBaseCompensation: String
    @State private var maxBaseCompensation: String
    @State private var minTotalCompensation: String
    @State private var maxTotalCompensation: String
    @State private var saveErrorMessage: String?

    init(
        company: CompanyProfile,
        detailViewModel: ApplicationDetailViewModel,
        snapshot: CompanySalarySnapshot? = nil
    ) {
        self.company = company
        self.detailViewModel = detailViewModel
        self.snapshot = snapshot
        _roleTitle = State(initialValue: snapshot?.roleTitle ?? "")
        _location = State(initialValue: snapshot?.location ?? "")
        _sourceName = State(initialValue: snapshot?.sourceName ?? "Manual")
        _sourceURLString = State(initialValue: snapshot?.sourceURLString ?? "")
        _notes = State(initialValue: snapshot?.notes ?? "")
        _confidenceNotes = State(initialValue: snapshot?.confidenceNotes ?? "")
        _currency = State(initialValue: snapshot?.currency ?? .usd)
        _minBaseCompensation = State(initialValue: snapshot?.minBaseCompensation.map(String.init) ?? "")
        _maxBaseCompensation = State(initialValue: snapshot?.maxBaseCompensation.map(String.init) ?? "")
        _minTotalCompensation = State(initialValue: snapshot?.minTotalCompensation.map(String.init) ?? "")
        _maxTotalCompensation = State(initialValue: snapshot?.maxTotalCompensation.map(String.init) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    TextField("Role Title", text: $roleTitle)
                    TextField("Location", text: $location)
                }

                Section("Source") {
                    TextField("Source Name", text: $sourceName)
                    TextField("Source URL", text: $sourceURLString)
                    Picker("Currency", selection: $currency) {
                        ForEach(Currency.allCases) { currency in
                            Text(currency.rawValue).tag(currency)
                        }
                    }
                }

                Section("Compensation") {
                    TextField("Min Base", text: $minBaseCompensation)
                    TextField("Max Base", text: $maxBaseCompensation)
                    TextField("Min Total", text: $minTotalCompensation)
                    TextField("Max Total", text: $maxTotalCompensation)
                }

                Section {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                    TextEditor(text: $confidenceNotes)
                        .frame(minHeight: 100)
                } header: {
                    Text("Notes / Confidence")
                }
            }
            .navigationTitle(snapshot == nil ? "Add Salary Snapshot" : "Edit Salary Snapshot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(snapshot == nil ? "Save" : "Update") {
                        save()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 620, minHeight: 560, idealHeight: 640)
            #endif
        }
        .alert("Unable to Save Salary Snapshot", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    private func save() {
        do {
            try detailViewModel.saveCompanySalarySnapshot(
                snapshot,
                company: company,
                roleTitle: roleTitle,
                location: location,
                sourceName: sourceName,
                sourceURLString: normalized(sourceURLString),
                notes: normalized(notes),
                confidenceNotes: normalized(confidenceNotes),
                currency: currency,
                minBaseCompensation: parseInteger(minBaseCompensation),
                maxBaseCompensation: parseInteger(maxBaseCompensation),
                minTotalCompensation: parseInteger(minTotalCompensation),
                maxTotalCompensation: parseInteger(maxTotalCompensation),
                context: modelContext
            )
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func parseInteger(_ value: String) -> Int? {
        let trimmed = value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : Int(trimmed)
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ApplicationOverviewNotesSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var application: JobApplication
    let viewModel: ApplicationDetailViewModel

    @State private var isEditing = false
    @State private var draftMarkdown: String = ""
    @State private var saveErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Overview Notes", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                if isEditing {
                    Button("Cancel") {
                        draftMarkdown = application.overviewMarkdown ?? ""
                        isEditing = false
                    }
                    .buttonStyle(.plain)

                    Button("Save") {
                        saveNotes()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)
                } else {
                    Button(application.overviewMarkdown?.isEmpty == false ? "Edit" : "Add Notes") {
                        draftMarkdown = application.overviewMarkdown ?? ""
                        isEditing = true
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $draftMarkdown)
                        .frame(minHeight: 180)

                    Text("Markdown supported. Use headings, lists, emphasis, and links for a living application summary.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else if let overview = normalized(application.overviewMarkdown) {
                VStack(alignment: .leading, spacing: 10) {
                    MarkdownPreviewText(markdown: overview)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Evergreen notes that stay pinned above the activity history.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No overview notes yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Capture recruiter context, interview themes, role-fit thinking, or anything you want to keep pinned outside the dated timeline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
        .onAppear {
            draftMarkdown = application.overviewMarkdown ?? ""
        }
        .alert("Unable to Save Notes", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func saveNotes() {
        do {
            try viewModel.saveOverviewMarkdown(
                normalized(draftMarkdown),
                for: application,
                context: modelContext
            )
            draftMarkdown = application.overviewMarkdown ?? ""
            isEditing = false
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct MarkdownPreviewText: View {
    let markdown: String

    private var renderedMarkdown: AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    var body: some View {
        Text(renderedMarkdown)
            .font(.body)
            .textSelection(.enabled)
    }
}

struct ApplicationTaskEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let application: JobApplication
    let taskToEdit: ApplicationTask?

    @State private var title: String
    @State private var notes: String
    @State private var priority: Priority
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var saveErrorMessage: String?

    private let viewModel = ApplicationDetailViewModel()

    init(application: JobApplication, taskToEdit: ApplicationTask? = nil) {
        self.application = application
        self.taskToEdit = taskToEdit
        _title = State(initialValue: taskToEdit?.title ?? "")
        _notes = State(initialValue: taskToEdit?.notes ?? "")
        _priority = State(initialValue: taskToEdit?.priority ?? .medium)
        _dueDate = State(initialValue: taskToEdit?.dueDate ?? Date())
        _hasDueDate = State(initialValue: taskToEdit?.dueDate != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)

                    PriorityPicker(selection: $priority)

                    Toggle("Due Date", isOn: $hasDueDate)

                    if hasDueDate {
                        DatePicker("Due", selection: $dueDate, displayedComponents: .date)
                    }
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle(taskToEdit == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(taskToEdit == nil ? "Save" : "Update") {
                        saveTask()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 540, idealWidth: 620, minHeight: 420, idealHeight: 480)
            #endif
        }
        .alert("Unable to Save Task", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func saveTask() {
        do {
            try viewModel.saveTask(
                taskToEdit,
                title: title,
                notes: normalized(notes),
                dueDate: hasDueDate ? dueDate : nil,
                priority: priority,
                for: application,
                context: modelContext
            )
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ApplicationChecklistSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var application: JobApplication
    let viewModel: ApplicationDetailViewModel
    let onEditTask: (ApplicationTask) -> Void
    let onOpenTaskAction: (ApplicationTask) -> Void
    let onError: (String) -> Void

    @State private var showingCompletedTasks = false

    private var openTasks: [ApplicationTask] {
        application.sortedChecklistTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [ApplicationTask] {
        application.sortedChecklistTasks.filter(\.isCompleted)
    }

    private var emptyMessage: String {
        switch application.status {
        case .saved:
            return "Checklist items will appear automatically as you prep this role."
        case .applied:
            return "Pipeline will keep stage-based application follow-through here."
        case .interviewing:
            return "Interview prep steps will appear here when they apply to this role."
        case .offered:
            return "Offer-stage checklist items will appear here when they apply."
        case .rejected, .archived, .custom(_):
            return "No smart checklist items are active for this application."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Smart Checklist", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                if !openTasks.isEmpty {
                    Text("\(openTasks.count) open")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                }
            }

            if openTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No open checklist items")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(emptyMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                ForEach(openTasks) { task in
                    ApplicationTaskRow(
                        task: task,
                        actionLabel: task.actionKind == .none ? nil : "Open",
                        deleteLabel: "Dismiss",
                        deleteConfirmationTitle: "Dismiss Checklist Item",
                        deleteConfirmationMessage: "This checklist item will stay hidden for this application.",
                        onToggleCompletion: {
                            setCompletion(!task.isCompleted, for: task)
                        },
                        onAction: {
                            onOpenTaskAction(task)
                        },
                        onEdit: {
                            onEditTask(task)
                        },
                        onDelete: {
                            deleteTask(task)
                        }
                    )
                }
            }

            if !completedTasks.isEmpty {
                DisclosureGroup(
                    isExpanded: $showingCompletedTasks,
                    content: {
                        VStack(spacing: 12) {
                            ForEach(completedTasks) { task in
                                ApplicationTaskRow(
                                    task: task,
                                    actionLabel: task.actionKind == .none ? nil : "Open",
                                    deleteLabel: "Dismiss",
                                    deleteConfirmationTitle: "Dismiss Checklist Item",
                                    deleteConfirmationMessage: "This checklist item will stay hidden for this application.",
                                    onToggleCompletion: {
                                        setCompletion(false, for: task)
                                    },
                                    onAction: {
                                        onOpenTaskAction(task)
                                    },
                                    onEdit: {
                                        onEditTask(task)
                                    },
                                    onDelete: {
                                        deleteTask(task)
                                    }
                                )
                            }
                        }
                        .padding(.top, 12)
                    },
                    label: {
                        Text("Completed (\(completedTasks.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                )
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
    }

    private func setCompletion(_ isCompleted: Bool, for task: ApplicationTask) {
        do {
            try viewModel.setTaskCompletion(isCompleted, for: task, in: application, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func deleteTask(_ task: ApplicationTask) {
        do {
            try viewModel.deleteTask(task, from: application, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct ApplicationTasksSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var application: JobApplication
    let viewModel: ApplicationDetailViewModel
    let onAddTask: () -> Void
    let onEditTask: (ApplicationTask) -> Void
    let onError: (String) -> Void

    @State private var showingCompletedTasks = false

    private var openTasks: [ApplicationTask] {
        application.sortedManualTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [ApplicationTask] {
        application.sortedManualTasks.filter(\.isCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Tasks", systemImage: "checklist")
                    .font(.headline)

                Spacer()

                Button("Add Task") {
                    onAddTask()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
            }

            if openTasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No open tasks")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Track prep work, follow-through, and deadlines specific to this application.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                ForEach(openTasks) { task in
                    ApplicationTaskRow(
                        task: task,
                        onToggleCompletion: {
                            setCompletion(!task.isCompleted, for: task)
                        },
                        onEdit: {
                            onEditTask(task)
                        },
                        onDelete: {
                            deleteTask(task)
                        }
                    )
                }
            }

            if !completedTasks.isEmpty {
                DisclosureGroup(
                    isExpanded: $showingCompletedTasks,
                    content: {
                        VStack(spacing: 12) {
                            ForEach(completedTasks) { task in
                                ApplicationTaskRow(
                                    task: task,
                                    onToggleCompletion: {
                                        setCompletion(false, for: task)
                                    },
                                    onEdit: {
                                        onEditTask(task)
                                    },
                                    onDelete: {
                                        deleteTask(task)
                                    }
                                )
                            }
                        }
                        .padding(.top, 12)
                    },
                    label: {
                        Text("Completed (\(completedTasks.count))")
                            .font(.subheadline.weight(.semibold))
                    }
                )
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
    }

    private func setCompletion(_ isCompleted: Bool, for task: ApplicationTask) {
        do {
            try viewModel.setTaskCompletion(isCompleted, for: task, in: application, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }

    private func deleteTask(_ task: ApplicationTask) {
        do {
            try viewModel.deleteTask(task, from: application, context: modelContext)
        } catch {
            onError(error.localizedDescription)
        }
    }
}

private struct ApplicationChecklistSuggestionsSection: View {
    @Bindable var viewModel: ChecklistSuggestionsViewModel

    private var buttonTitle: String {
        viewModel.hasGeneratedSuggestions ? "Refresh Suggestions" : "Generate Suggestions"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("AI Suggestions", systemImage: "sparkles")
                    .font(.headline)

                Spacer()

                Button(buttonTitle) {
                    Task {
                        await viewModel.generate()
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
                .disabled(viewModel.isLoading)
            }

            Text("Optional ideas tailored to this role. Accepted suggestions become normal tasks and do not change the base checklist.")
                .font(.caption)
                .foregroundColor(.secondary)

            if viewModel.isLoading && viewModel.pendingSuggestions.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Generating role-specific next steps...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else if viewModel.pendingSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No pending suggestions")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("Generate optional, job-specific next steps after you add more notes, company research, or interview context.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                ForEach(viewModel.pendingSuggestions) { suggestion in
                    ApplicationChecklistSuggestionRow(
                        suggestion: suggestion,
                        onAccept: {
                            viewModel.accept(suggestion)
                        },
                        onDismiss: {
                            viewModel.dismiss(suggestion)
                        }
                    )
                }
            }
        }
    }
}

private struct ApplicationTaskRow: View {
    let task: ApplicationTask
    var actionLabel: String? = nil
    var deleteLabel: String = "Delete"
    var deleteConfirmationTitle: String = "Delete Task"
    var deleteConfirmationMessage: String = "Are you sure you want to delete this task?"
    let onToggleCompletion: () -> Void
    var onAction: (() -> Void)? = nil
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onToggleCompletion) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(task.isCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(task.displayTitle)
                            .font(.subheadline.weight(.semibold))
                            .strikethrough(task.isCompleted, color: .secondary)

                        PriorityFlag(priority: task.priority)
                    }

                    if let dueDate = task.dueDate {
                        Text(dueDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundColor(dueDate < Calendar.current.startOfDay(for: Date()) && !task.isCompleted ? .red : .secondary)
                    }

                    if let notes = task.normalizedNotes {
                        Text(notes)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                HStack(spacing: 12) {
                    if let actionLabel, let onAction {
                        Button(actionLabel) {
                            onAction()
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.accent)
                    }

                    Button("Edit") {
                        onEdit()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Text(deleteLabel)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        deleteConfirmationTitle,
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button(deleteLabel, role: .destructive) {
                            onDelete()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text(deleteConfirmationMessage)
                    }
                }
                .font(.caption)
            }
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

private struct ApplicationChecklistSuggestionRow: View {
    let suggestion: ApplicationChecklistSuggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(suggestion.displayTitle)
                .font(.subheadline.weight(.semibold))

            if let rationale = suggestion.normalizedRationale {
                Text(rationale)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button("Add as Task") {
                    onAccept()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)

                Button("Dismiss", role: .destructive) {
                    onDismiss()
                }
                .buttonStyle(.plain)
            }
            .font(.caption.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

struct JobPostingSection: View {
    let urlString: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Job Posting", systemImage: "link")
                    .font(.headline)

                Spacer()

                if let url = URL(string: urlString) {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Text("Open Link")
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 12))
                        }
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                }
            }

            Text(urlString)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

private struct JobDescriptionDenoiseReviewSheet: View {
    let originalDescription: String
    let cleanedDescription: String
    let onCancel: () -> Void
    let onReplace: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                header
                Divider().overlay(DesignSystem.Colors.divider(colorScheme))
                comparisonBody
                Divider().overlay(DesignSystem.Colors.divider(colorScheme))
                footer
            }
            .frame(width: 980, height: 680)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
            #else
            NavigationStack {
                comparisonBody
                    .navigationTitle("Review Denoised Description")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                onCancel()
                                dismiss()
                            }
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Replace") {
                                onReplace()
                            }
                        }
                    }
            }
            .presentationDetents([.large])
            #endif
        }
    }

    #if os(macOS)
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review Denoised Description")
                    .font(.title3.weight(.semibold))
                Text("Compare the original import against the cleaned version before replacing it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .foregroundColor(.secondary)
                    .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.bordered)

            Button("Replace Description") {
                onReplace()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
    #endif

    private var comparisonBody: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    comparisonPane(title: "Original", description: originalDescription)
                    comparisonPane(title: "Cleaned", description: cleanedDescription)
                }

                VStack(spacing: 16) {
                    comparisonPane(title: "Original", description: originalDescription)
                    comparisonPane(title: "Cleaned", description: cleanedDescription)
                }
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    private func comparisonPane(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)

            ScrollView {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 260, maxHeight: .infinity, alignment: .topLeading)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

private struct InterviewLearningsSection: View {
    let application: JobApplication
    let applications: [JobApplication]
    let latestSnapshot: InterviewLearningSnapshot?
    let onDebriefLatest: () -> Void
    let onViewLearnings: () -> Void

    private let builder = InterviewLearningContextBuilder()

    private var context: InterviewLearningContext {
        builder.build(from: applications)
    }

    private var previewSignals: [String] {
        if let latestSnapshot {
            let combined = latestSnapshot.strengths + latestSnapshot.growthAreas
            if !combined.isEmpty {
                return Array(combined.prefix(3))
            }
        }

        return Array(builder.fallbackInsights(from: context).recommendedFocusAreas.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Interview Learnings", systemImage: "brain")
                    .font(.headline)

                Spacer()

                Button("View Learnings") {
                    onViewLearnings()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
            }

            HStack(spacing: 10) {
                metricCapsule("\(application.pendingInterviewDebriefs.count) pending debrief\(application.pendingInterviewDebriefs.count == 1 ? "" : "s")")
                metricCapsule("\(context.questionCount) question\(context.questionCount == 1 ? "" : "s")")
                metricCapsule("\(context.companyCount) compan\(context.companyCount == 1 ? "y" : "ies")")
            }

            if previewSignals.isEmpty {
                Text("Save a few interview debriefs to surface personalized strengths, patterns, and prep prompts.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(previewSignals, id: \.self) { signal in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "sparkles")
                                .foregroundColor(DesignSystem.Colors.accent)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(signal)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            HStack(spacing: 12) {
                Button {
                    onDebriefLatest()
                } label: {
                    Label("Debrief Latest", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)

                Button {
                    onViewLearnings()
                } label: {
                    Label("Question Bank", systemImage: "text.book.closed")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func metricCapsule(_ value: String) -> some View {
        Text(value)
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct InterviewDebriefSheet: View {
    @State var viewModel: InterviewDebriefViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationStack {
            Form {
                Section("Questions Asked") {
                    ForEach($bindableViewModel.questions) { $question in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Question asked", text: $question.prompt, axis: .vertical)
                                .lineLimit(2 ... 4)

                            Picker("Category", selection: $question.category) {
                                ForEach(InterviewQuestionCategory.allCases) { category in
                                    Text(category.displayName).tag(category)
                                }
                            }

                            TextField("How did you answer?", text: $question.answerNotes, axis: .vertical)
                                .lineLimit(2 ... 4)

                            TextField("Interviewer hint or context", text: $question.interviewerHint, axis: .vertical)
                                .lineLimit(1 ... 3)

                            HStack {
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    viewModel.removeQuestion(id: question.id)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        viewModel.addQuestion()
                    } label: {
                        Label("Add Question", systemImage: "plus")
                    }
                }

                Section("Confidence") {
                    Stepper(value: $bindableViewModel.confidence, in: 1 ... 5) {
                        HStack {
                            Text("How confident do you feel?")
                            Spacer()
                            Text("\(viewModel.confidence)/5")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section("Reflection") {
                    TextField("What went well?", text: $bindableViewModel.whatWentWell, axis: .vertical)
                        .lineLimit(2 ... 5)
                    TextField("What would you do differently?", text: $bindableViewModel.wouldDoDifferently, axis: .vertical)
                        .lineLimit(2 ... 5)
                    TextField("Anything else to remember?", text: $bindableViewModel.overallNotes, axis: .vertical)
                        .lineLimit(2 ... 5)
                }

                Section("Follow-up Action Items") {
                    Text("These become real tasks when you save the debrief.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach($bindableViewModel.followUpItems) { $item in
                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Action item", text: $item.title)
                            TextField("Optional notes", text: $item.notes, axis: .vertical)
                                .lineLimit(1 ... 3)

                            HStack {
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    viewModel.removeFollowUpItem(id: item.id)
                                }
                                .font(.caption)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Button {
                        viewModel.addFollowUpItem()
                    } label: {
                        Label("Add Action Item", systemImage: "plus")
                    }
                }
            }
            .navigationTitle("Interview Debrief")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            try viewModel.save()
                            dismiss()
                        } catch {
                            viewModel.errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 620, idealWidth: 720, minHeight: 640, idealHeight: 760)
            #endif
        }
        .alert("Unable to Save Debrief", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }
}

private struct InterviewLearningsView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case patterns = "Patterns"
        case questionBank = "Question Bank"

        var id: String { rawValue }
    }

    @State var viewModel: InterviewLearningsViewModel
    @State private var selectedTab: Tab = .patterns
    @State private var searchText = ""
    @State private var selectedCategory: InterviewQuestionCategory?
    @State private var selectedCompany = "All Companies"
    @State private var selectedStage = "All Stages"
    @Environment(\.dismiss) private var dismiss

    private var effectiveSnapshot: InterviewLearningSnapshot? {
        viewModel.snapshot ?? viewModel.fallbackSnapshot
    }

    private var availableCompanies: [String] {
        ["All Companies"] + Array(Set(viewModel.questionBankEntries.map(\.companyName))).sorted()
    }

    private var availableStages: [String] {
        ["All Stages"] + Array(
            Set(viewModel.questionBankEntries.compactMap { $0.interviewStage?.displayName })
        ).sorted()
    }

    private var filteredEntries: [InterviewQuestionBankEntry] {
        viewModel.questionBankEntries.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.question.localizedCaseInsensitiveContains(searchText) ||
                entry.companyName.localizedCaseInsensitiveContains(searchText) ||
                entry.role.localizedCaseInsensitiveContains(searchText) ||
                (entry.answerNotes?.localizedCaseInsensitiveContains(searchText) ?? false)

            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            let matchesCompany = selectedCompany == "All Companies" || entry.companyName == selectedCompany
            let matchesStage = selectedStage == "All Stages" || entry.interviewStage?.displayName == selectedStage
            return matchesSearch && matchesCategory && matchesCompany && matchesStage
        }
    }

    private var groupedEntries: [(InterviewQuestionCategory, [InterviewQuestionBankEntry])] {
        Dictionary(grouping: filteredEntries, by: \.category)
            .map { category, entries in
                (category, entries.sorted { $0.occurredAt > $1.occurredAt })
            }
            .sorted { $0.0.displayName < $1.0.displayName }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedTab == .patterns {
                    patternsView
                } else {
                    questionBankView
                }
            }
            .navigationTitle("Interview Learnings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading)
                }
            }
            #if os(macOS)
            .frame(minWidth: 760, idealWidth: 900, minHeight: 640, idealHeight: 760)
            #endif
        }
        .task {
            viewModel.load()
        }
        .alert("Interview Learnings Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.error ?? "An unknown error occurred.")
        }
    }

    private var patternsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.isLoading {
                    ProgressView("Refreshing interview learnings…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let effectiveSnapshot {
                    patternCard("Strengths", items: effectiveSnapshot.strengths, icon: "bolt.fill", tint: .green)
                    patternCard("Growth Areas", items: effectiveSnapshot.growthAreas, icon: "scope", tint: .orange)
                    patternCard("Recurring Themes", items: effectiveSnapshot.recurringThemes, icon: "repeat", tint: .blue)
                    patternCard("Company Patterns", items: effectiveSnapshot.companyPatterns, icon: "building.2.fill", tint: .purple)
                    patternCard("Recommended Focus", items: effectiveSnapshot.recommendedFocusAreas, icon: "target", tint: DesignSystem.Colors.accent)
                } else {
                    ContentUnavailableView(
                        "No learnings yet",
                        systemImage: "brain",
                        description: Text("Complete at least one interview debrief to build your personal question bank and patterns.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                }
            }
            .padding(20)
        }
    }

    private var questionBankView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SearchBar(text: $searchText, placeholder: "Search questions, companies, or notes...")

                HStack(spacing: 12) {
                    Menu {
                        Button("All Categories") { selectedCategory = nil }
                        ForEach(InterviewQuestionCategory.allCases) { category in
                            Button(category.displayName) {
                                selectedCategory = category
                            }
                        }
                    } label: {
                        filterLabel(selectedCategory?.displayName ?? "All Categories")
                    }

                    Menu {
                        ForEach(availableCompanies, id: \.self) { company in
                            Button(company) { selectedCompany = company }
                        }
                    } label: {
                        filterLabel(selectedCompany)
                    }

                    Menu {
                        ForEach(availableStages, id: \.self) { stage in
                            Button(stage) { selectedStage = stage }
                        }
                    } label: {
                        filterLabel(selectedStage)
                    }

                    Spacer()
                }

                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No matching questions",
                        systemImage: "text.book.closed",
                        description: Text("Adjust your filters or complete more debriefs to build the question bank.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ForEach(groupedEntries, id: \.0) { category, entries in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(category.displayName)
                                .font(.headline)

                            ForEach(entries, id: \.id) { entry in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(entry.question)
                                        .font(.subheadline.weight(.semibold))
                                    Text("\(entry.companyName) • \(entry.role)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if let stage = entry.interviewStage {
                                        Text(stage.displayName)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if let answerNotes = entry.answerNotes, !answerNotes.isEmpty {
                                        Text(answerNotes)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                                .appCard(cornerRadius: 14, elevated: true, shadow: false)
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func patternCard(_ title: String, items: [String], icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline)
            }

            if items.isEmpty {
                Text("Not enough history yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundColor(tint)
                            .padding(.top, 6)
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func filterLabel(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            Image(systemName: "chevron.down")
                .font(.caption2)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.12))
        .clipShape(Capsule())
    }
}

private struct RejectionAnalysisSection: View {
    @Environment(\.colorScheme) private var colorScheme

    let application: JobApplication
    let latestSnapshot: RejectionLearningSnapshot?
    let recoverySuggestions: [RejectionRecoverySuggestion]
    let hasConfiguredAI: Bool
    let isAnalyzing: Bool
    let onFillLog: () -> Void
    let onAnalyze: () -> Void

    private var latestLog: RejectionLog? {
        application.latestRejectionLog
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Rejection Analysis", systemImage: "arrow.counterclockwise.circle")
                    .font(.headline)

                Spacer()

                if application.latestRejectionActivity != nil {
                    Button(latestLog == nil ? "Complete Log" : "Edit Log") {
                        onFillLog()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            if application.needsRejectionLog {
                bannerCard(
                    title: "Rejection log missing",
                    body: "Capture the stage, likely reason, and any feedback so Pipeline can turn this rejection into a useful learning signal.",
                    accent: .orange,
                    actionTitle: "Complete Log",
                    action: onFillLog
                )
            } else if let latestLog {
                loggedState(log: latestLog)
            }

            if !recoverySuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recovery Suggestions")
                        .font(.subheadline.weight(.semibold))

                    ForEach(recoverySuggestions) { suggestion in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.subheadline.weight(.medium))
                            Text(suggestion.body)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                        )
                    }
                }
            }

            if let latestSnapshot, latestSnapshot.rejectionCount >= 3 {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Global Signals")
                            .font(.subheadline.weight(.semibold))

                        Spacer()

                        Button {
                            onAnalyze()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.accent)
                        .disabled(isAnalyzing)
                    }

                    if isAnalyzing {
                        ProgressView("Refreshing rejection learnings…")
                            .font(.caption)
                    }

                    signalGroup(title: "Patterns", items: latestSnapshot.patternSignals, icon: "waveform.path.ecg")
                    signalGroup(title: "Targeting", items: latestSnapshot.targetingSignals, icon: "scope")
                    signalGroup(title: "Process", items: latestSnapshot.processSignals, icon: "list.clipboard")
                }
            } else if application.latestRejectionLog != nil {
                bannerCard(
                    title: hasConfiguredAI ? "Analyze patterns after a few more rejections" : "Configure AI to analyze rejection patterns",
                    body: hasConfiguredAI
                        ? "Pipeline will start surfacing higher-confidence rejection learnings once you have at least 3 logged rejections."
                        : "Capture rejection logs now, then add an AI provider in Settings when you want Pipeline to synthesize patterns and recovery ideas.",
                    accent: hasConfiguredAI ? .blue : .secondary,
                    actionTitle: hasConfiguredAI ? "Analyze Now" : nil,
                    action: onAnalyze
                )
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func loggedState(log: RejectionLog) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                capsule(log.stageCategory.displayName)
                capsule(log.reasonCategory.displayName)
                capsule(log.feedbackSource.displayName)
                if log.doNotReapply {
                    capsule("Do Not Reapply", tint: .red)
                }
            }

            if let feedback = log.feedbackText {
                detailBlock(title: "Feedback", body: feedback)
            }

            if let reflection = log.candidateReflection {
                detailBlock(title: "Reflection", body: reflection)
            }
        }
    }

    private func signalGroup(title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if items.isEmpty {
                Text("No \(title.lowercased()) yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items, id: \.self) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundColor(DesignSystem.Colors.accent)
                            .padding(.top, 2)
                        Text(item)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func bannerCard(
        title: String,
        body: String,
        accent: Color,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            Text(body)
                .font(.caption)
                .foregroundColor(.secondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func detailBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(body)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func capsule(_ text: String, tint: Color = .secondary) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(colorScheme == .dark ? 0.18 : 0.10))
            .clipShape(Capsule())
    }
}

struct RejectionLogSheet: View {
    @State var viewModel: RejectionLogEditorViewModel
    @Environment(\.dismiss) private var dismiss

    let onSaved: (() -> Void)?

    var body: some View {
        @Bindable var bindableViewModel = viewModel

        NavigationStack {
            Form {
                Section("Stage") {
                    Picker("Rejected At", selection: $bindableViewModel.stageCategory) {
                        ForEach(RejectionStageCategory.allCases) { stage in
                            Text(stage.displayName).tag(stage)
                        }
                    }
                }

                Section("Reason") {
                    Picker("Likely Reason", selection: $bindableViewModel.reasonCategory) {
                        ForEach(RejectionReasonCategory.allCases) { reason in
                            Text(reason.displayName).tag(reason)
                        }
                    }

                    Picker("Feedback Source", selection: $bindableViewModel.feedbackSource) {
                        ForEach(RejectionFeedbackSource.allCases) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                }

                Section("Notes") {
                    TextField("Feedback received", text: $bindableViewModel.feedbackText, axis: .vertical)
                        .lineLimit(2 ... 5)

                    TextField("Your reflection", text: $bindableViewModel.candidateReflection, axis: .vertical)
                        .lineLimit(2 ... 5)

                    Toggle("Do not suggest re-applying here", isOn: $bindableViewModel.doNotReapply)
                }
            }
            .navigationTitle("Rejection Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(viewModel.isSaving ? "Saving…" : "Save") {
                        Task {
                            do {
                                try await viewModel.save()
                                onSaved?()
                                dismiss()
                            } catch {
                                viewModel.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(viewModel.isSaving)
                }
            }
            #if os(macOS)
            .frame(minWidth: 540, idealWidth: 620, minHeight: 520, idealHeight: 620)
            #endif
        }
        .alert("Unable to Save Rejection Log", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        }
    }
}

#Preview {
    NavigationStack {
        JobDetailView(
            application: JobApplication(
                companyName: "Apple",
                role: "Senior iOS Developer",
                location: "Cupertino, CA",
                jobURL: "https://jobs.apple.com/12345",
                jobDescription: "We are looking for an experienced iOS developer to join our team...",
                status: .interviewing,
                priority: .high,
                source: .companyWebsite,
                platform: .linkedin,
                interviewStage: .technicalRound1,
                currency: .usd,
                salaryMin: 180000,
                salaryMax: 250000,
                appliedDate: Date().addingTimeInterval(-86400 * 14),
                nextFollowUpDate: Date().addingTimeInterval(86400 * 2)
            )
        )
    }
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
            AIModelRate.self
        ],
        inMemory: true
    )
}
