import SwiftUI
import SwiftData

struct ApplicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]

    @Binding var selectedFilter: SidebarFilter
    @Binding var selectedApplication: JobApplication?
    @Binding var searchText: String

    @State private var viewModel = ApplicationListViewModel()

    private var filteredApplications: [JobApplication] {
        viewModel.searchText = searchText
        viewModel.selectedFilter = selectedFilter
        return viewModel.filterApplications(applications)
    }

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 350), spacing: 16)
    ]

    var body: some View {
        Group {
            if filteredApplications.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(filteredApplications) { application in
                            JobCardView(
                                application: application,
                                isSelected: selectedApplication?.id == application.id
                            )
                            .onTapGesture {
                                selectedApplication = application
                            }
                            .contextMenu {
                                contextMenuItems(for: application)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: filteredApplications.count)
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No Applications", systemImage: "briefcase")
            } description: {
                Text("Add your first job application to get started")
            }
        } else {
            ContentUnavailableView.search(text: searchText)
        }
    }

    @ViewBuilder
    private func contextMenuItems(for application: JobApplication) -> some View {
        Button {
            selectedApplication = application
        } label: {
            Label("View Details", systemImage: "eye")
        }

        Divider()

        Menu("Change Status") {
            ForEach(ApplicationStatus.allCases) { status in
                Button {
                    application.status = status
                    application.updateTimestamp()
                    try? modelContext.save()
                } label: {
                    Label(status.displayName, systemImage: status.icon)
                }
            }
        }

        Menu("Set Priority") {
            ForEach(Priority.allCases) { priority in
                Button {
                    application.priority = priority
                    application.updateTimestamp()
                    try? modelContext.save()
                } label: {
                    Label(priority.displayName, systemImage: priority.icon)
                }
            }
        }

        Divider()

        if application.status != .archived {
            Button {
                application.status = .archived
                application.updateTimestamp()
                try? modelContext.save()
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }

        Button(role: .destructive) {
            if selectedApplication?.id == application.id {
                selectedApplication = nil
            }
            modelContext.delete(application)
            try? modelContext.save()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

#Preview {
    ApplicationListView(
        selectedFilter: .constant(.all),
        selectedApplication: .constant(nil),
        searchText: .constant("")
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
