import SwiftUI
import SwiftData

struct AddInterviewLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let application: JobApplication
    let logToEdit: InterviewLog?

    @State private var interviewType: InterviewStage = .phoneScreen
    @State private var date: Date = Date()
    @State private var interviewerName: String = ""
    @State private var rating: Int = 3
    @State private var notes: String = ""
    @State private var saveErrorMessage: String?

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
            application.status = .interviewing
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
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
