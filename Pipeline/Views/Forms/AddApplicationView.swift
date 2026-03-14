import SwiftUI
import SwiftData
import PipelineKit

struct AddApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AddEditApplicationViewModel()
    @State private var aiViewModel: AIParsingViewModel
    @State private var selectedTab: AddTab = .manual
    @State private var saveErrorMessage: String?
    @State private var rejectionPromptActivity: ApplicationActivity?
    @State private var dismissAfterRejectionPrompt = false
    @Environment(\.colorScheme) private var colorScheme
    let settingsViewModel: SettingsViewModel
    let onOpenSettings: (() -> Void)?
    let onReplayOnboarding: (() -> Void)?

    enum AddTab: String, CaseIterable {
        case manual = "Manual Entry"
        case aiParse = "AI Parse"

        var icon: String {
            switch self {
            case .manual: return "square.and.pencil"
            case .aiParse: return "wand.and.stars"
            }
        }
    }

    init(
        settingsViewModel: SettingsViewModel = SettingsViewModel(),
        onOpenSettings: (() -> Void)? = nil,
        onReplayOnboarding: (() -> Void)? = nil
    ) {
        self.settingsViewModel = settingsViewModel
        _aiViewModel = State(initialValue: AIParsingViewModel(settingsViewModel: settingsViewModel))
        self.onOpenSettings = onOpenSettings
        self.onReplayOnboarding = onReplayOnboarding
    }

    var body: some View {
        Group {
            #if os(macOS)
            VStack(spacing: 0) {
                header

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                tabBar

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                ScrollView {
                    Group {
                        switch selectedTab {
                        case .manual:
                            ManualEntryFormView(viewModel: viewModel)
                        case .aiParse:
                            AIParseFormView(
                                aiViewModel: aiViewModel,
                                onOpenSettings: onOpenSettings,
                                onReplayOnboarding: onReplayOnboarding
                            )
                        }
                    }
                    .padding(24)
                }

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                footer
            }
            .frame(width: 760, height: 620)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
            #else
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        ForEach(AddTab.allCases, id: \.self) { tab in
                            TabButton(
                                title: tab.rawValue,
                                icon: tab.icon,
                                isSelected: selectedTab == tab
                            ) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedTab = tab
                                }
                            }
                        }
                    }
                    .padding(12)
                    .appCard(cornerRadius: 16, elevated: true, shadow: false)
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Divider()

                    TabView(selection: $selectedTab) {
                        ManualEntryFormView(viewModel: viewModel)
                            .tag(AddTab.manual)

                        AIParseFormView(
                            aiViewModel: aiViewModel,
                            onOpenSettings: onOpenSettings,
                            onReplayOnboarding: onReplayOnboarding
                        )
                        .tag(AddTab.aiParse)
                    }
                    .tabViewStyle(.automatic)
                }
                .navigationTitle("Add Application")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(primaryActionTitle) {
                            switch selectedTab {
                            case .manual:
                                saveApplication()
                            case .aiParse:
                                applyParsedDataAndContinue()
                            }
                        }
                        .disabled(primaryActionDisabled)
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
                    application: activity.application ?? JobApplication(
                        companyName: viewModel.companyName,
                        role: viewModel.role,
                        location: viewModel.location
                    ),
                    modelContext: modelContext,
                    settingsViewModel: settingsViewModel
                ),
                onSaved: {
                    dismiss()
                }
            )
        }
        .onAppear {
            aiViewModel.modelContext = modelContext
        }
    }

    private func saveApplication() {
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

    private func applyParsedDataAndContinue() {
        guard aiViewModel.parsedData != nil else { return }

        aiViewModel.applyToViewModel(viewModel)
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = .manual
        }
    }

    private var primaryActionTitle: String {
        switch selectedTab {
        case .manual:
            return "Add Application"
        case .aiParse:
            return aiViewModel.parsedData == nil ? "Parse to Continue" : "Apply & Continue"
        }
    }

    private var primaryActionDisabled: Bool {
        switch selectedTab {
        case .manual:
            return !viewModel.isValid
        case .aiParse:
            return aiViewModel.parsedData == nil
        }
    }

    private var footerMessage: String {
        switch selectedTab {
        case .manual:
            return viewModel.validationErrors.first ?? "Review the draft and save when the required fields look right."
        case .aiParse:
            if aiViewModel.parsedData != nil {
                return "Parsed fields are ready. Apply them to Manual Entry before saving."
            }
            return "Paste a job URL, run AI Parse, then review the populated fields in Manual Entry."
        }
    }

    private var footerMessageIcon: String {
        switch selectedTab {
        case .manual:
            return viewModel.validationErrors.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle"
        case .aiParse:
            return aiViewModel.parsedData == nil ? "wand.and.stars" : "checkmark.circle.fill"
        }
    }

    #if os(macOS)
    private var header: some View {
        HStack {
            Text("Add New Application")
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
    }

    private var tabBar: some View {
        HStack(spacing: 10) {
            ForEach(AddTab.allCases, id: \.self) { tab in
                TabButton(
                    title: tab.rawValue,
                    icon: tab.icon,
                    isSelected: selectedTab == tab
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(12)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(footerMessage, systemImage: footerMessageIcon)
                .font(.caption)
                .foregroundColor(.secondary)
                .labelStyle(.titleAndIcon)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Button(primaryActionTitle) {
                switch selectedTab {
                case .manual:
                    saveApplication()
                case .aiParse:
                    applyParsedDataAndContinue()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
            .disabled(primaryActionDisabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
    #endif
    }

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))

                Text(title)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .medium))
            }
            .foregroundColor(isSelected ? DesignSystem.Colors.accent : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10)
                            : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.45 : 0.24)
                            : DesignSystem.Colors.stroke(colorScheme),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    AddApplicationView()
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
            FollowUpStep.self,
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
