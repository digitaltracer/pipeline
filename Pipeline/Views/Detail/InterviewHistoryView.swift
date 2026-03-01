import SwiftUI
import PipelineKit

struct InterviewHistoryView: View {
    let logs: [InterviewLog]
    let onAddLog: () -> Void
    let onEditLog: (InterviewLog) -> Void
    let onDeleteLog: (InterviewLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Interview History", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)

                Spacer()

                Button {
                    onAddLog()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("Add Log")
                    }
                    .font(.subheadline)
                    .foregroundColor(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if logs.isEmpty {
                emptyState
            } else {
                ForEach(logs) { log in
                    InterviewLogRow(
                        log: log,
                        onEdit: { onEditLog(log) },
                        onDelete: { onDeleteLog(log) }
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

            Text("No interview logs yet")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Add First Log") {
                onAddLog()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.regular)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

struct InterviewLogRow: View {
    let log: InterviewLog
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(log.interviewType.displayName)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 6) {
                        Text(log.date.formatted(date: .long, time: .omitted))
                        if let interviewer = log.interviewerName, !interviewer.isEmpty {
                            Text("•")
                            Text(interviewer)
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Spacer()

                StarRatingDisplay(rating: log.rating, size: 12)
            }

            if let notes = log.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }

            HStack {
                Spacer()
                Button {
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.9))
            }
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
        .confirmationDialog(
            "Delete Interview Log",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete this interview log?")
        }
    }
}

#Preview {
    InterviewHistoryView(
        logs: InterviewLog.sampleData,
        onAddLog: {},
        onEditLog: { _ in },
        onDeleteLog: { _ in }
    )
    .padding()
}
