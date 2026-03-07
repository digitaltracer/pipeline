import SwiftUI
import SwiftData
import PipelineKit

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
    @State private var showingDeleteAlert = false
    @State private var showingInterviewPrep = false
    @State private var showingFollowUpDrafter = false
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
                ForEach(ApplicationActivityKind.allCases) { kind in
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
            Contact.self,
            ApplicationContactLink.self,
            ApplicationActivity.self,
            ApplicationAttachment.self,
            ResumeMasterRevision.self,
            ResumeJobSnapshot.self,
            AIUsageRecord.self,
            AIModelRate.self
        ],
        inMemory: true
    )
}
