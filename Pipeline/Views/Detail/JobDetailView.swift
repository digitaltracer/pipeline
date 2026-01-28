import SwiftUI
import SwiftData

struct JobDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var application: JobApplication

    @State private var viewModel = ApplicationDetailViewModel()
    @State private var showingEditSheet = false
    @State private var showingAddInterviewLog = false
    @State private var showingDeleteAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                JobDetailHeaderView(
                    application: application,
                    onStatusChange: { status in
                        viewModel.application = application
                        viewModel.updateStatus(status, context: modelContext)
                    },
                    onPriorityChange: { priority in
                        viewModel.application = application
                        viewModel.updatePriority(priority, context: modelContext)
                    }
                )

                Divider()

                // Fields Grid
                JobDetailFieldsView(application: application)

                // Job URL
                if let urlString = application.jobURL, !urlString.isEmpty {
                    Divider()
                    JobURLSection(urlString: urlString)
                }

                // Interview Stage Indicator
                if application.status == .interviewing {
                    Divider()
                    InterviewStageIndicator(
                        currentStage: application.interviewStage,
                        onStageChange: { stage in
                            viewModel.application = application
                            viewModel.updateInterviewStage(stage, context: modelContext)
                        }
                    )
                }

                // Job Description
                if let description = application.jobDescription, !description.isEmpty {
                    Divider()
                    JobDescriptionView(description: description)
                }

                // Interview History
                Divider()
                InterviewHistoryView(
                    logs: application.sortedInterviewLogs,
                    onAddLog: {
                        showingAddInterviewLog = true
                    },
                    onDeleteLog: { log in
                        viewModel.application = application
                        viewModel.deleteInterviewLog(log, context: modelContext)
                    }
                )

                Divider()

                // Action Buttons
                actionButtons
            }
            .padding()
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            EditApplicationView(application: application)
        }
        .sheet(isPresented: $showingAddInterviewLog) {
            AddInterviewLogView(application: application)
        }
        .alert("Delete Application", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                viewModel.application = application
                viewModel.delete(context: modelContext)
            }
        } message: {
            Text("Are you sure you want to delete this application? This action cannot be undone.")
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                showingAddInterviewLog = true
            } label: {
                Label("Add Log", systemImage: "plus.bubble")
            }
            .buttonStyle(.bordered)

            if application.status != .archived {
                Button {
                    viewModel.application = application
                    viewModel.archive(context: modelContext)
                } label: {
                    Label("Archive", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}

struct JobURLSection: View {
    let urlString: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job Posting")
                .font(.headline)

            HStack {
                Text(urlString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                if let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Open", systemImage: "arrow.up.forward.square")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
            }
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
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
