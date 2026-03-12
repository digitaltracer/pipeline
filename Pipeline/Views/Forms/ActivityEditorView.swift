import SwiftUI
import SwiftData
import PipelineKit

struct ActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]

    let application: JobApplication
    let activityToEdit: ApplicationActivity?
    let defaultKind: ApplicationActivityKind

    @State private var selectedKind: ApplicationActivityKind
    @State private var occurredAt: Date
    @State private var selectedContactID: UUID?
    @State private var interviewStage: InterviewStage
    @State private var scheduledDurationMinutes: Int
    @State private var rating: Int
    @State private var emailSubject: String
    @State private var emailBodySnapshot: String
    @State private var notes: String
    @State private var saveErrorMessage: String?

    private let viewModel = ApplicationDetailViewModel()

    init(
        application: JobApplication,
        activityToEdit: ApplicationActivity? = nil,
        defaultKind: ApplicationActivityKind = .note
    ) {
        self.application = application
        self.activityToEdit = activityToEdit
        self.defaultKind = defaultKind
        _selectedKind = State(initialValue: activityToEdit?.kind ?? defaultKind)
        _occurredAt = State(initialValue: activityToEdit?.occurredAt ?? Date())
        _selectedContactID = State(initialValue: activityToEdit?.contact?.id)
        _interviewStage = State(initialValue: activityToEdit?.interviewStage ?? .phoneScreen)
        _scheduledDurationMinutes = State(initialValue: activityToEdit?.scheduledDurationMinutes ?? 60)
        _rating = State(initialValue: activityToEdit?.rating ?? 3)
        _emailSubject = State(initialValue: activityToEdit?.emailSubject ?? "")
        _emailBodySnapshot = State(initialValue: activityToEdit?.emailBodySnapshot ?? "")
        _notes = State(initialValue: activityToEdit?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    Picker("Activity Type", selection: $selectedKind) {
                        ForEach(ApplicationActivityKind.manualCases) { kind in
                            Label(kind.displayName, systemImage: kind.icon)
                                .tag(kind)
                        }
                    }

                    DatePicker(selectedKind == .interview ? "Interview Start" : "Occurred At", selection: $occurredAt)

                    Picker("Contact", selection: $selectedContactID) {
                        Text("No Contact").tag(nil as UUID?)
                        ForEach(suggestedContacts) { contact in
                            Text(contact.fullName).tag(Optional(contact.id))
                        }
                    }
                }

                if selectedKind == .interview {
                    Section("Interview") {
                        Picker("Stage", selection: $interviewStage) {
                            ForEach(InterviewStage.allCases) { stage in
                                Text(stage.displayName).tag(stage)
                            }
                        }

                        Stepper(value: $scheduledDurationMinutes, in: 15 ... 240, step: 15) {
                            HStack {
                                Text("Duration")
                                Spacer()
                                Text("\(scheduledDurationMinutes) min")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Stepper(value: $rating, in: 1 ... 5) {
                            HStack {
                                Text("Rating")
                                Spacer()
                                Text("\(rating)/5")
                                    .foregroundColor(.secondary)
                            }
                        }

                        Text(interviewTimingHelperText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if selectedKind == .email {
                    Section("Email") {
                        TextField("Subject", text: $emailSubject)
                        TextEditor(text: $emailBodySnapshot)
                            .frame(minHeight: 140)
                    }
                }

                Section(selectedKind == .email ? "Notes" : "Details") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle(activityToEdit == nil ? "New Activity" : "Edit Activity")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(activityToEdit == nil ? "Save" : "Update") {
                        saveActivity()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 620)
            #endif
        }
        .alert("Unable to Save Activity", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var suggestedContacts: [Contact] {
        let linkedContacts = application.sortedContactLinks.compactMap(\.contact)
        let unlinkedContacts = contacts.filter { contact in
            !linkedContacts.contains(where: { $0.id == contact.id })
        }
        return linkedContacts + unlinkedContacts
    }

    private func saveActivity() {
        do {
            try viewModel.saveActivity(
                activityToEdit,
                kind: selectedKind,
                occurredAt: occurredAt,
                notes: normalized(notes),
                contact: selectedContactID.flatMap { id in
                    contacts.first(where: { $0.id == id })
                },
                interviewStage: selectedKind == .interview ? interviewStage : nil,
                scheduledDurationMinutes: selectedKind == .interview ? scheduledDurationMinutes : nil,
                rating: selectedKind == .interview ? rating : nil,
                emailSubject: selectedKind == .email ? normalized(emailSubject) : nil,
                emailBodySnapshot: selectedKind == .email ? normalized(emailBodySnapshot) : nil,
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

    private var interviewTimingHelperText: String {
        if occurredAt > Date() {
            let endDate = Calendar.current.date(
                byAdding: .minute,
                value: scheduledDurationMinutes,
                to: occurredAt
            ) ?? occurredAt
            return "This interview is scheduled. Pipeline will remind you to debrief 30 minutes after \(endDate.formatted(date: .omitted, time: .shortened))."
        }

        return "If you schedule interviews here in advance, Pipeline can send a debrief reminder after they end."
    }
}
