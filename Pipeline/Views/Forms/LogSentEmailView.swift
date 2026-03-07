import SwiftUI
import SwiftData
import PipelineKit

struct LogSentEmailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let application: JobApplication
    let suggestedSubject: String
    let suggestedBody: String

    @State private var occurredAt = Date()
    @State private var selectedContactID: UUID?
    @State private var subject: String
    @State private var bodySnapshot: String
    @State private var notes: String = ""
    @State private var saveErrorMessage: String?

    private let viewModel = ApplicationDetailViewModel()

    init(application: JobApplication, suggestedSubject: String, suggestedBody: String) {
        self.application = application
        self.suggestedSubject = suggestedSubject
        self.suggestedBody = suggestedBody
        _subject = State(initialValue: suggestedSubject)
        _bodySnapshot = State(initialValue: suggestedBody)
        _selectedContactID = State(initialValue: application.primaryContactLink?.contact?.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Delivery") {
                    DatePicker("Sent At", selection: $occurredAt)

                    Picker("Contact", selection: $selectedContactID) {
                        Text("No Contact").tag(nil as UUID?)
                        ForEach(application.sortedContactLinks.compactMap(\.contact)) { contact in
                            Text(contact.fullName).tag(Optional(contact.id))
                        }
                    }
                }

                Section("Email") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $bodySnapshot)
                        .frame(minHeight: 180)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 120)
                }
            }
            .navigationTitle("Log Sent Email")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Email") {
                        saveEmailLog()
                    }
                }
            }
            #if os(macOS)
            .frame(minWidth: 620, idealWidth: 680, minHeight: 560, idealHeight: 620)
            #endif
        }
        .alert("Unable to Log Email", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private func saveEmailLog() {
        do {
            try viewModel.saveActivity(
                nil,
                kind: .email,
                occurredAt: occurredAt,
                notes: normalized(notes),
                contact: selectedContactID.flatMap { id in
                    application.sortedContactLinks.compactMap(\.contact).first(where: { $0.id == id })
                },
                interviewStage: nil,
                rating: nil,
                emailSubject: normalized(subject),
                emailBodySnapshot: normalized(bodySnapshot),
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
