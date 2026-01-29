import SwiftUI
import SwiftData

struct ApplicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    @Binding var searchText: String

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 340), spacing: 16)
    ]

    private var statusMenuOptions: [ApplicationStatus] {
        let defaults = ApplicationStatus.allCases.sorted { $0.sortOrder < $1.sortOrder }
        let customs = CustomValuesStore.customStatuses()
            .map { ApplicationStatus(rawValue: $0) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

        var seen = Set<String>()
        return (defaults + customs).filter { status in
            let key = status.rawValue.lowercased()
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    var body: some View {
        Group {
            if applications.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(applications) { application in
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: applications.count)
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
            ForEach(statusMenuOptions) { status in
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
        applications: [],
        selectedApplication: .constant(nil),
        searchText: .constant("")
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
