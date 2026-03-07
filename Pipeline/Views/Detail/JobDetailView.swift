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
    @Bindable var application: JobApplication
    var onClose: (() -> Void)? = nil
    var onSelectContact: ((Contact) -> Void)? = nil

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
    @State private var showingFollowUpDrafter = false
    @State private var showingCompanyWorkspace = false
    @State private var companyWorkspaceTab: CompanyWorkspaceTab = .overview
    @State private var actionErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            JobDetailHeaderView(
                application: application,
                onClose: onClose,
                onDelete: { showingDeleteAlert = true },
                onStatusChange: { status in
                    do {
                        try viewModel.updateStatus(status, for: application, context: modelContext)
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
                        JobDescriptionView(description: description)
                    }

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
        .sheet(isPresented: $showingInterviewPrep) {
            InterviewPrepView(
                viewModel: InterviewPrepViewModel(
                    application: application,
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
        .task(id: application.id) {
            if application.company == nil {
                do {
                    _ = try viewModel.ensureCompanyProfile(for: application, context: modelContext)
                } catch {
                    actionErrorMessage = error.localizedDescription
                }
            }
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

            if application.status == .interviewing {
                Button {
                    showingInterviewPrep = true
                } label: {
                    Label("Prep", systemImage: "sparkles")
                        .frame(width: 110)
                }
                .buttonStyle(.bordered)
            }

            Button {
                showingFollowUpDrafter = true
            } label: {
                Label("Follow Up", systemImage: "envelope.badge")
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
        VStack(alignment: .leading, spacing: 16) {
            companyCard(
                title: "Research Run",
                subtitle: company.lastResearchedAt.map { "Last refreshed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Run structured AI research against the company profile and saved links."
            ) {
                VStack(alignment: .leading, spacing: 12) {
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
                if let summary = company.lastResearchSummary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("No AI research summary yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            companyCard(title: "Sources", subtitle: "Fetched and manual links retained on the company profile.") {
                if company.sortedResearchSources.isEmpty && company.sourceLinks.isEmpty {
                    Text("No sources saved yet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(company.sortedResearchSources) { source in
                            sourceRow(source)
                        }

                        ForEach(company.sourceLinks.filter { link in
                            !company.sortedResearchSources.contains(where: { $0.urlString == link })
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
                                Text(snapshot.requestStatus == .succeeded ? "Succeeded" : "Failed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(snapshot.requestStatus == .succeeded ? .green : .red)
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(source.title)
                    .font(.subheadline.weight(.medium))
                Text(source.sourceKind.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let excerpt = source.contentExcerpt, !excerpt.isEmpty {
                    Text(excerpt)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                if let errorMessage = source.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                Text(source.fetchStatus.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(source.fetchStatus == .fetched ? .green : .secondary)

                if let url = source.normalizedURL {
                    Button("Open") {
                        openURL(url)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
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

private struct ApplicationTasksSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var application: JobApplication
    let viewModel: ApplicationDetailViewModel
    let onAddTask: () -> Void
    let onEditTask: (ApplicationTask) -> Void
    let onError: (String) -> Void

    @State private var showingCompletedTasks = false

    private var openTasks: [ApplicationTask] {
        application.sortedTasks.filter { !$0.isCompleted }
    }

    private var completedTasks: [ApplicationTask] {
        application.sortedTasks.filter(\.isCompleted)
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

private struct ApplicationTaskRow: View {
    let task: ApplicationTask
    let onToggleCompletion: () -> Void
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
                    Button("Edit") {
                        onEdit()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(DesignSystem.Colors.accent)

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
                            onDelete()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("Are you sure you want to delete this task?")
                    }
                }
                .font(.caption)
            }
        }
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
            ApplicationTask.self,
            ApplicationAttachment.self,
            ResumeMasterRevision.self,
            ResumeJobSnapshot.self,
            AIUsageRecord.self,
            AIModelRate.self
        ],
        inMemory: true
    )
}
