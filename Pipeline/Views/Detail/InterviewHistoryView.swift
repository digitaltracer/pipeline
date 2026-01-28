import SwiftUI

struct InterviewHistoryView: View {
    let logs: [InterviewLog]
    let onAddLog: () -> Void
    let onDeleteLog: (InterviewLog) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Interview History")
                    .font(.headline)

                Spacer()

                Button {
                    onAddLog()
                } label: {
                    Label("Add Log", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if logs.isEmpty {
                emptyState
            } else {
                ForEach(logs) { log in
                    InterviewLogRow(log: log, onDelete: {
                        onDeleteLog(log)
                    })
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
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

struct InterviewLogRow: View {
    let log: InterviewLog
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Type Badge
                HStack(spacing: 4) {
                    Image(systemName: log.interviewType.icon)
                        .font(.caption)
                    Text(log.interviewType.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .foregroundColor(log.interviewType.color)
                .background(log.interviewType.color.opacity(0.1))
                .clipShape(Capsule())

                Spacer()

                // Date
                Text(log.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Delete Button
                Button {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .opacity(0.6)
            }

            // Interviewer & Rating
            HStack {
                if let interviewer = log.interviewerName, !interviewer.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "person")
                            .font(.caption)
                        Text(interviewer)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }

                Spacer()

                StarRatingDisplay(rating: log.rating, size: 12)
            }

            // Notes
            if let notes = log.notes, !notes.isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
        }
        .padding()
        .background(Color(.textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
        onDeleteLog: { _ in }
    )
    .padding()
}
