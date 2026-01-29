import SwiftUI
import SwiftData

struct EditApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let application: JobApplication
    @State private var viewModel: AddEditApplicationViewModel

    init(application: JobApplication) {
        self.application = application
        self._viewModel = State(initialValue: AddEditApplicationViewModel(application: application))
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            HStack {
                Text("Edit Application")
                    .font(.title3)
                    .fontWeight(.semibold)

                Spacer()

                Button {
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

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            ScrollView {
                ManualEntryFormView(viewModel: viewModel)
                    .padding(24)
            }

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)

                Button("Save Changes") {
                    if viewModel.save(context: modelContext) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(!viewModel.isValid)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(DesignSystem.Colors.surfaceElevated(colorScheme))
        }
        .frame(width: 760, height: 620)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        #else
        NavigationStack {
            ManualEntryFormView(viewModel: viewModel)
                .navigationTitle("Edit Application")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
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
        #endif
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
