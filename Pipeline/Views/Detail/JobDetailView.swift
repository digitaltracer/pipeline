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
    @State private var showingTaskEditor = false
    @State private var editingTask: ApplicationTask?
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
