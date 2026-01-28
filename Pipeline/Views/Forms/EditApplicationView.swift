import SwiftUI
import SwiftData

struct EditApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let application: JobApplication
    @State private var viewModel: AddEditApplicationViewModel

    init(application: JobApplication) {
        self.application = application
        self._viewModel = State(initialValue: AddEditApplicationViewModel(application: application))
    }

    var body: some View {
        NavigationStack {
            ManualEntryFormView(viewModel: viewModel)
                .navigationTitle("Edit Application")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            if viewModel.save(context: modelContext) {
                                dismiss()
                            }
                        }
                        .disabled(!viewModel.isValid)
                    }
                }
                .frame(minWidth: 500, minHeight: 600)
        }
    }
}

#Preview {
    EditApplicationView(
        application: JobApplication(
            companyName: "Apple",
            role: "Senior iOS Developer",
            location: "Cupertino, CA",
            status: .interviewing,
            priority: .high
        )
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
