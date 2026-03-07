import SwiftUI
import PipelineKit

struct ApplicationTimelineView: View {
    let activities: [ApplicationActivity]
    var onAddActivity: ((ApplicationActivityKind) -> Void)? = nil
    var onEditActivity: ((ApplicationActivity) -> Void)? = nil
    var onDeleteActivity: ((ApplicationActivity) -> Void)? = nil
    var emptyTitle: String = "No activity yet"
    var emptyDescription: String = "Log interviews, calls, emails, texts, and notes to build a full timeline for this application."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Activity Timeline", systemImage: "clock.arrow.circlepath")
                    .font(.headline)

                Spacer()

                if let onAddActivity {
                    Menu {
                        ForEach(ApplicationActivityKind.allCases) { kind in
                            Button {
                                onAddActivity(kind)
                            } label: {
                                Label(kind.displayName, systemImage: kind.icon)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                            Text("Add Activity")
                        }
                        .font(.subheadline)
                        .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if activities.isEmpty {
                emptyState
            } else {
                ForEach(activities) { activity in
                    ActivityRowView(
                        activity: activity,
                        onEdit: onEditActivity.map { callback in { callback(activity) } },
                        onDelete: onDeleteActivity.map { callback in { callback(activity) } }
                    )
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.questionmark")
                .font(.largeTitle)
                .foregroundColor(.secondary)

            Text(emptyTitle)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(emptyDescription)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

private struct ActivityRowView: View {
    let activity: ApplicationActivity
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: activity.kind.icon)
                            .foregroundColor(activity.kind.color)

                        Text(activity.title)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }

                    HStack(spacing: 6) {
                        Text(activity.occurredAt.formatted(date: .long, time: .shortened))
                        if let contact = activity.contact {
                            Text("•")
                            Text(contact.fullName)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)

                    if activity.kind == .interview, let stage = activity.interviewStage {
                        Text(stage.displayName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let rating = activity.rating {
                    StarRatingDisplay(rating: rating, size: 12)
                }
            }

            if let summary = activity.summary, !summary.isEmpty {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(4)
            }

            if onEdit != nil || onDelete != nil {
                HStack {
                    Spacer()

                    if let onEdit {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignSystem.Colors.accent)
                    }

                    if let onDelete {
                        Button(role: .destructive) {
                            showingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.red.opacity(0.9))
                        .confirmationDialog(
                            "Delete Activity",
                            isPresented: $showingDeleteConfirmation,
                            titleVisibility: .visible
                        ) {
                            Button("Delete", role: .destructive) {
                                onDelete()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Are you sure you want to delete this activity entry?")
                        }
                    }
                }
            }
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}
