import SwiftUI
import PipelineKit

struct JobDetailHeaderView: View {
    let application: JobApplication
    var onClose: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let onStatusChange: (ApplicationStatus) -> Void
    let onPriorityChange: (Priority) -> Void
    var onQueueMembershipChange: ((Bool) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

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

    private var logoURL: String? {
        application.googleS2FaviconURL(size: 96)?.absoluteString
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            CompanyAvatar(
                companyName: application.companyName,
                logoURL: logoURL,
                size: 54,
                cornerRadius: 16
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(application.role)
                    .font(.title3)
                    .fontWeight(.bold)

                Text(application.companyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    Menu {
                        ForEach(statusMenuOptions) { status in
                            Button {
                                onStatusChange(status)
                            } label: {
                                Label(status.displayName, systemImage: status.icon)
                            }
                        }
                    } label: {
                        StatusBadge(status: application.status, showIcon: true)
                    }

                    Menu {
                        ForEach(Priority.allCases) { priority in
                            Button {
                                onPriorityChange(priority)
                            } label: {
                                Label(priority.displayName, systemImage: priority.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            PriorityFlag(priority: application.priority, showLabel: true, size: 12)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(application.priority.color.opacity(0.14))
                        .clipShape(Capsule())
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if let onQueueMembershipChange, application.status == .saved {
                    Button {
                        onQueueMembershipChange(!application.isQueuedForApplyLater)
                    } label: {
                        Image(systemName: application.isQueuedForApplyLater ? "bookmark.fill" : "bookmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(application.isQueuedForApplyLater ? DesignSystem.Colors.accent : .secondary)
                    .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                    .clipShape(Circle())
                    .help(application.isQueuedForApplyLater ? "Remove from apply queue" : "Add to apply queue")
                }

                if let onDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red.opacity(0.9))
                    .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                    .clipShape(Circle())
                }

                if let onClose {
                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                    .clipShape(Circle())
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}

#Preview {
    VStack(spacing: 20) {
        JobDetailHeaderView(
            application: JobApplication(
                companyName: "Apple",
                role: "Senior iOS Developer",
                location: "Cupertino, CA",
                status: .interviewing,
                priority: .high
            ),
            onStatusChange: { _ in },
            onPriorityChange: { _ in }
        )

        JobDetailHeaderView(
            application: JobApplication(
                companyName: "Google",
                role: "Staff Engineer",
                location: "Mountain View, CA",
                status: .applied,
                priority: .medium
            ),
            onStatusChange: { _ in },
            onPriorityChange: { _ in }
        )
    }
    .padding()
}
