import SwiftUI
import SwiftData
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct ApplicationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    @Binding var searchText: String
    @State private var actionErrorMessage: String?

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
                            .applicationCardHandCursor()
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
        .alert("Action Failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
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
                    applyStatus(status, to: application)
                } label: {
                    Label(status.displayName, systemImage: status.icon)
                }
            }
        }

        Menu("Set Priority") {
            ForEach(Priority.allCases) { priority in
                Button {
                    applyPriority(priority, to: application)
                } label: {
                    Label(priority.displayName, systemImage: priority.icon)
                }
            }
        }

        Divider()

        if application.status != .archived {
            Button {
                applyStatus(.archived, to: application)
            } label: {
                Label("Archive", systemImage: "archivebox")
            }
        }

        Button(role: .destructive) {
            delete(application)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func applyStatus(_ status: ApplicationStatus, to application: JobApplication) {
        let previousStatus = application.status
        let previousAppliedDate = application.appliedDate
        application.status = status
        if (status == .applied || status == .interviewing), application.appliedDate == nil {
            application.appliedDate = Date()
        }
        application.updateTimestamp()

        do {
            try modelContext.save()
            Task { @MainActor in
                await NotificationService.shared.syncFollowUpReminder(for: application)
            }
        } catch {
            application.status = previousStatus
            application.appliedDate = previousAppliedDate
            actionErrorMessage = error.localizedDescription
        }
    }

    private func applyPriority(_ priority: Priority, to application: JobApplication) {
        let previousPriority = application.priority
        application.priority = priority
        application.updateTimestamp()

        do {
            try modelContext.save()
        } catch {
            application.priority = previousPriority
            actionErrorMessage = error.localizedDescription
        }
    }

    private func delete(_ application: JobApplication) {
        if selectedApplication?.id == application.id {
            selectedApplication = nil
        }

        modelContext.delete(application)
        do {
            try modelContext.save()
            Task { await NotificationService.shared.removeNotifications(for: application.id) }
        } catch {
            modelContext.rollback()
            actionErrorMessage = error.localizedDescription
        }
    }
}

private extension View {
#if os(macOS)
    func applicationCardHandCursor() -> some View {
        onContinuousHover { phase in
            switch phase {
            case .active:
                NSCursor.pointingHand.set()
            case .ended:
                NSCursor.arrow.set()
            }
        }
    }
#else
    func applicationCardHandCursor() -> some View { self }
#endif
}

#Preview {
    ApplicationListView(
        applications: [],
        selectedApplication: .constant(nil),
        searchText: .constant("")
    )
    .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
