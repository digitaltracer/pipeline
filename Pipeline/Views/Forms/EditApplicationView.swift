import SwiftUI
import SwiftData
import PipelineKit

struct EditApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    let application: JobApplication
    @State private var viewModel: AddEditApplicationViewModel
    @State private var saveErrorMessage: String?
    @State private var rejectionPromptActivity: ApplicationActivity?
    @State private var dismissAfterRejectionPrompt = false

    init(application: JobApplication) {
        self.application = application
        self._viewModel = State(initialValue: AddEditApplicationViewModel(application: application))
    }

    var body: some View {
        Group {
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
                        saveChanges()
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
                                saveChanges()
                            }
                            .disabled(!viewModel.isValid)
                        }
                    }
                    .frame(minWidth: 500, minHeight: 600)
            }
            #endif
        }
        .alert("Unable to Save", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .sheet(item: $rejectionPromptActivity, onDismiss: {
            if dismissAfterRejectionPrompt {
                dismiss()
            }
        }) { activity in
            RejectionLogSheet(
                viewModel: RejectionLogEditorViewModel(
                    activity: activity,
                    application: application,
                    modelContext: modelContext,
                    settingsViewModel: SettingsViewModel()
                ),
                onSaved: {
                    dismiss()
                }
            )
        }
    }

    private func saveChanges() {
        do {
            let result = try viewModel.save(context: modelContext)
            if let activityID = result.rejectionStatusActivityID,
               let activity = result.application.sortedActivities.first(where: { $0.id == activityID }) {
                dismissAfterRejectionPrompt = true
                rejectionPromptActivity = activity
            } else {
                dismiss()
            }
        } catch {
            saveErrorMessage = error.localizedDescription
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
            RejectionLog.self,
            InterviewQuestionEntry.self,
            InterviewLearningSnapshot.self,
            RejectionLearningSnapshot.self,
            ApplicationTask.self,
            ApplicationChecklistSuggestion.self,
            ApplicationAttachment.self,
            CoverLetterDraft.self,
            JobMatchAssessment.self,
            ATSCompatibilityAssessment.self,
            ATSCompatibilityScanRun.self
        ],
        inMemory: true
    )
}
