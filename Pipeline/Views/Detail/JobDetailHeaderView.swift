import SwiftUI
import PipelineKit

struct JobDetailHeaderView: View {
    let application: JobApplication
    var onClose: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    let onStatusChange: (ApplicationStatus) -> Void
    let onPriorityChange: (Priority) -> Void
    var onQueueMembershipChange: ((Bool) -> Void)? = nil

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
                size: 58,
                cornerRadius: 14
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
                    .interactiveHandCursor()

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
                    .interactiveHandCursor()
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if let onQueueMembershipChange, application.status == .saved {
                    HeaderActionButton(
                        systemImage: application.isQueuedForApplyLater ? "bookmark.fill" : "bookmark",
                        foregroundColor: application.isQueuedForApplyLater ? DesignSystem.Colors.accent : .secondary,
                        helpText: application.isQueuedForApplyLater ? "Remove from apply queue" : "Add to apply queue"
                    ) {
                        onQueueMembershipChange(!application.isQueuedForApplyLater)
                    }
                }

                if let onDelete {
                    HeaderActionButton(
                        systemImage: "trash",
                        foregroundColor: .red.opacity(0.9),
                        helpText: "Delete application",
                        role: .destructive
                    ) {
                        onDelete()
                    }
                }

                if let onClose {
                    HeaderActionButton(
                        systemImage: "xmark",
                        foregroundColor: .secondary,
                        helpText: "Close details"
                    ) {
                        onClose()
                    }
                }
            }
        }
        .padding(DesignSystem.Spacing.md)
        .appCard(cornerRadius: DesignSystem.Radius.card, elevated: true, shadow: true, stroke: false)
    }
}

private struct HeaderActionButton: View {
    let systemImage: String
    let foregroundColor: Color
    let helpText: String
    var role: ButtonRole? = nil
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(role: role, action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .interactiveHandCursor()
        .fastTooltip(helpText)
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
