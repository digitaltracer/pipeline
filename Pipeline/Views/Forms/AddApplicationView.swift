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
    @Environment(\.colorScheme) private var colorScheme
    let onOpenSettings: (() -> Void)?

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
        onOpenSettings: (() -> Void)? = nil
    ) {
        _aiViewModel = State(initialValue: AIParsingViewModel(settingsViewModel: settingsViewModel))
        self.onOpenSettings = onOpenSettings
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
                                formViewModel: viewModel,
                                onApplyParsedData: { selectedTab = .manual },
                                onOpenSettings: onOpenSettings
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
                    // Underlined Tab Bar
                    HStack(spacing: 0) {
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
                    .padding(.horizontal)
                    .padding(.top, 8)

                    Divider()

                    TabView(selection: $selectedTab) {
                        ManualEntryFormView(viewModel: viewModel)
                            .tag(AddTab.manual)

                        AIParseFormView(
                            aiViewModel: aiViewModel,
                            formViewModel: viewModel,
                            onApplyParsedData: {
                                selectedTab = .manual
                            },
                            onOpenSettings: onOpenSettings
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
                        Button("Save") {
                            do {
                                try viewModel.save(context: modelContext)
                                dismiss()
                            } catch {
                                saveErrorMessage = error.localizedDescription
                            }
                        }
                        .disabled(!viewModel.isValid || selectedTab == .aiParse)
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
        .onAppear {
            aiViewModel.modelContext = modelContext
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
        HStack(spacing: 0) {
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
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)

            Button("Add Application") {
                do {
                    try viewModel.save(context: modelContext)
                    dismiss()
                } catch {
                    saveErrorMessage = error.localizedDescription
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .disabled(!viewModel.isValid || selectedTab == .aiParse)
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

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(title)
                        .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                }
                .foregroundColor(isSelected ? .blue : .secondary)

                Rectangle()
                    .fill(isSelected ? Color.blue : Color.clear)
                    .frame(height: 2)
            }
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
                ApplicationTask.self,
                ApplicationAttachment.self
            ],
            inMemory: true
        )
}
