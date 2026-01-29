import SwiftUI
import SwiftData

struct AddApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AddEditApplicationViewModel()
    @State private var aiViewModel = AIParsingViewModel()
    @State private var selectedTab: AddTab = .manual
    @Environment(\.colorScheme) private var colorScheme

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

    var body: some View {
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
                            onApplyParsedData: { selectedTab = .manual }
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
                        }
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
                        if viewModel.save(context: modelContext) {
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.isValid || selectedTab == .aiParse)
                }
            }
            .frame(minWidth: 500, minHeight: 600)
        }
        #endif
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
                if viewModel.save(context: modelContext) {
                    dismiss()
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
        .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
