import SwiftUI
import SwiftData

struct AddApplicationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel = AddEditApplicationViewModel()
    @State private var aiViewModel = AIParsingViewModel()
    @State private var selectedTab: AddTab = .manual

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
        NavigationStack {
            VStack(spacing: 0) {
                // Tab Picker
                Picker("Entry Method", selection: $selectedTab) {
                    ForEach(AddTab.allCases, id: \.self) { tab in
                        Label(tab.rawValue, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                Divider()

                // Tab Content
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
            #if os(macOS)
            .navigationSubtitle(selectedTab.rawValue)
            #endif
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
                    .disabled(!viewModel.isValid || selectedTab == .aiParse)
                }
            }
            .frame(minWidth: 500, minHeight: 600)
        }
    }
}

#Preview {
    AddApplicationView()
        .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
