import SwiftUI
import SwiftData
import PipelineKit

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext
    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    let currentResumeRevisionID: UUID?
    let matchPreferences: JobMatchPreferences
    var onboardingProgress: OnboardingProgress? = nil
    var onOnboardingAction: ((OnboardingAction) -> Void)? = nil
    var onHideOnboardingGuidance: (() -> Void)? = nil

    @State private var viewModel = KanbanViewModel()
    @State private var actionErrorMessage: String?
    @State private var rejectionPromptActivity: ApplicationActivity?

    var body: some View {
        Group {
            if applications.isEmpty, let onOnboardingAction {
                OnboardingFeatureCalloutCard(
                    title: "Kanban becomes useful once your search has live stages",
                    message: "After you add a few real applications, this board will separate saved, applied, interviewing, and offered work into one drag-and-drop view.",
                    icon: "rectangle.split.3x1",
                    actions: [
                        OnboardingCardAction(
                            id: "kanban-add",
                            title: "Add Application",
                            systemImage: "plus.circle.fill",
                            action: .addApplication,
                            isProminent: true
                        ),
                        OnboardingCardAction(
                            id: "kanban-tour",
                            title: "Replay Tour",
                            systemImage: "play.rectangle",
                            action: .replayTour
                        )
                    ],
                    onAction: onOnboardingAction,
                    onMute: onboardingProgress?.shouldShowSetupGuidance == true ? onHideOnboardingGuidance : nil
                )
                .padding(20)
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 14) {
                        if applications.count < 3, let onOnboardingAction {
                            OnboardingFeatureCalloutCard(
                                title: "Add a few more applications to see stage flow clearly",
                                message: "Kanban works best once you have real movement across statuses. Add or import more jobs to make the board actionable.",
                                icon: "rectangle.split.3x1",
                                actions: [
                                    OnboardingCardAction(
                                        id: "kanban-add-more",
                                        title: "Add Application",
                                        systemImage: "plus.circle.fill",
                                        action: .addApplication,
                                        isProminent: true
                                    )
                                ],
                                onAction: onOnboardingAction,
                                onMute: onboardingProgress?.shouldShowSetupGuidance == true ? onHideOnboardingGuidance : nil
                            )
                        }

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
                    }
                    .padding(16)
                }
            }
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
