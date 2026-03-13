import SwiftUI
import SwiftData
import PipelineKit

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext
    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    let currentResumeRevisionID: UUID?
    let matchPreferences: JobMatchPreferences

    @State private var viewModel = KanbanViewModel()
    @State private var actionErrorMessage: String?
    @State private var rejectionPromptActivity: ApplicationActivity?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(KanbanViewModel.columns, id: \.rawValue) { status in
                    KanbanColumnView(
                        status: status,
                        applications: viewModel.applicationsForColumn(status, from: applications),
                        selectedApplication: $selectedApplication,
                        currentResumeRevisionID: currentResumeRevisionID,
                        matchPreferences: matchPreferences,
                        onDrop: { uuid, targetStatus in
                            guard let app = applications.first(where: { $0.id == uuid }) else { return }
                            do {
                                let result = try viewModel.moveApplication(app, to: targetStatus, context: modelContext)
                                if result.needsRejectionLogPrompt, let activityID = result.statusActivityID {
                                    rejectionPromptActivity = app.sortedActivities.first(where: { $0.id == activityID })
                                }
                            } catch {
                                actionErrorMessage = error.localizedDescription
                            }
                        }
                    )
                }
            }
            .padding(16)
        }
        .sheet(item: $rejectionPromptActivity) { activity in
            RejectionLogSheet(
                viewModel: RejectionLogEditorViewModel(
                    activity: activity,
                    application: activity.application ?? JobApplication(
                        companyName: "",
                        role: "",
                        location: ""
                    ),
                    modelContext: modelContext,
                    settingsViewModel: SettingsViewModel()
                ),
                onSaved: nil
            )
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
}
