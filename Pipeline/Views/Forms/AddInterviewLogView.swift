import SwiftUI
import SwiftData
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct AddInterviewLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let application: JobApplication
    let logToEdit: InterviewLog?

    @State private var interviewType: InterviewStage = .phoneScreen
    @State private var date: Date = Date()
    @State private var interviewerName: String = ""
    @State private var rating: Int = 3
    @State private var notes: String = ""
    @State private var saveErrorMessage: String?
    @State private var isNotesEditorActive = false
    #if os(macOS)
    @State private var showingDatePickerPopover = false
    #endif

    init(application: JobApplication, logToEdit: InterviewLog? = nil) {
        self.application = application
        self.logToEdit = logToEdit
        _interviewType = State(initialValue: logToEdit?.interviewType ?? .phoneScreen)
        _date = State(initialValue: logToEdit?.date ?? Date())
        _interviewerName = State(initialValue: logToEdit?.interviewerName ?? "")
        _rating = State(initialValue: logToEdit?.rating ?? 3)
        _notes = State(initialValue: logToEdit?.notes ?? "")
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                macHeader

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                ScrollView {
                    macFormContent
                        .padding(24)
                }

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                macFooter
            }
            .frame(width: 760, height: 650)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
            #else
            NavigationStack {
                Form {
                    Section("Interview Details") {
                        Picker("Interview Type", selection: $interviewType) {
                            ForEach(InterviewStage.allCases) { stage in
                                Label(stage.displayName, systemImage: stage.icon)
                                    .tag(stage)
                            }
                        }

                        DatePicker("Date & Time", selection: $date)

                        TextField("Interviewer Name (optional)", text: $interviewerName)
                    }

                    Section("Rating") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How did it go?")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack {
                                Spacer()
                                StarRating(rating: $rating, size: 32)
                                Spacer()
                            }

                            Text(ratingDescription)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 8)
                    }

                    Section("Notes") {
                        TextEditor(text: $notes)
                            .frame(minHeight: 100)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle(isEditing ? "Edit Interview Log" : "Add Interview Log")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(isEditing ? "Update" : "Save") {
                            saveLog()
                        }
                    }
                }
                .frame(minWidth: 400, minHeight: 450)
            }
            #endif
        }
        .alert("Unable to Save Log", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var ratingDescription: String {
        switch rating {
        case 1: return "Went poorly - major concerns"
        case 2: return "Below average - some issues"
        case 3: return "Average - met expectations"
        case 4: return "Good - went well overall"
        case 5: return "Excellent - great experience!"
        default: return ""
        }
    }

    private var isEditing: Bool {
        logToEdit != nil
    }

    #if os(macOS)
    private var formattedInterviewDate: String {
        date.formatted(date: .numeric, time: .omitted)
    }
    #endif

    #if os(macOS)
    private var macHeader: some View {
        HStack {
            Text(isEditing ? "Edit Interview Log" : "Add Interview Log")
                .font(.title)
                .fontWeight(.semibold)

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }

    private var macFormContent: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Interview Round *")
                    .font(.title3)
                    .fontWeight(.medium)

                Picker("", selection: $interviewType) {
                    ForEach(InterviewStage.allCases) { stage in
                        Text(stage.displayName)
                            .tag(stage)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appInput()
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Date *")
                        .font(.title3)
                        .fontWeight(.medium)

                    HStack(spacing: 10) {
                        Text(formattedInterviewDate)
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Spacer(minLength: 8)

                        Image(systemName: "calendar")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        showingDatePickerPopover.toggle()
                    }
                    .popover(isPresented: $showingDatePickerPopover, arrowEdge: .bottom) {
                        DatePicker(
                            "Interview Date",
                            selection: $date,
                            displayedComponents: [.date]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .controlSize(.large)
                        .scaleEffect(1.22, anchor: .top)
                        .padding(10)
                        .fixedSize()
                    }
                    .onChange(of: date) { _, _ in
                        if showingDatePickerPopover {
                            showingDatePickerPopover = false
                        }
                    }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appInput()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Interviewer")
                        .font(.title3)
                        .fontWeight(.medium)

                    TextField("", text: $interviewerName, prompt: Text("Name or role"))
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                        .appInput()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Your Rating")
                    .font(.title3)
                    .fontWeight(.medium)

                StarRating(rating: $rating, size: 30, spacing: 12)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Notes *")
                    .font(.title3)
                    .fontWeight(.medium)

                ZStack(alignment: .topLeading) {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isNotesEditorActive {
                        Text("How did the interview go? What questions were asked? Any feedback received?")
                            .font(.body)
                            .foregroundColor(DesignSystem.Colors.placeholder(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .onTapGesture {
                            isNotesEditorActive = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didBeginEditingNotification)) { _ in
                            isNotesEditorActive = true
                        }
                        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didEndEditingNotification)) { _ in
                            isNotesEditorActive = false
                        }
                }
                .frame(minHeight: 180)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )
            }
        }
    }

    private var macFooter: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Button(isEditing ? "Update Log" : "Add Log") {
                saveLog()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
    #endif

    private func saveLog() {
        let normalizedInterviewer = interviewerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let logToEdit {
            logToEdit.interviewType = interviewType
            logToEdit.date = date
            logToEdit.interviewerName = normalizedInterviewer.isEmpty ? nil : normalizedInterviewer
            logToEdit.rating = rating
            logToEdit.notes = normalizedNotes.isEmpty ? nil : normalizedNotes
        } else {
            let log = InterviewLog(
                interviewType: interviewType,
                date: date,
                interviewerName: normalizedInterviewer.isEmpty ? nil : normalizedInterviewer,
                rating: rating,
                notes: normalizedNotes.isEmpty ? nil : normalizedNotes,
                application: application
            )
            modelContext.insert(log)
        }

        application.updateTimestamp()

        // Update interview stage if this is a later stage
        if let currentStage = application.interviewStage {
            if interviewType.sortOrder > currentStage.sortOrder {
                application.interviewStage = interviewType
            }
        } else {
            application.interviewStage = interviewType
        }

        // Ensure status is interviewing
        if application.status == .applied || application.status == .saved {
            let previousStatus = application.status
            application.status = .interviewing
            ApplicationTimelineRecorderService.recordStatusChange(
                for: application,
                from: previousStatus,
                to: application.status,
                in: modelContext
            )
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }
}

#Preview {
    AddInterviewLogView(
        application: JobApplication(
            companyName: "Apple",
            role: "Senior iOS Developer",
            location: "Cupertino, CA"
        )
    )
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
            InterviewQuestionEntry.self,
            InterviewLearningSnapshot.self,
            ApplicationTask.self,
            ApplicationChecklistSuggestion.self,
            ApplicationAttachment.self,
            CoverLetterDraft.self,
            JobMatchAssessment.self,
            ATSCompatibilityAssessment.self
        ],
        inMemory: true
    )
}
