import SwiftUI
import PipelineKit
#if os(macOS)
import AppKit
#endif

struct ContactsListView: View {
    let rows: [ContactRow]
    @Binding var selectedContact: Contact?
    @Binding var searchText: String
    var onAddContact: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 260, maximum: 320), spacing: 16)
    ]

    var body: some View {
        Group {
            if rows.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(rows) { row in
                            ContactCardView(row: row, isSelected: selectedContact?.id == row.contact.id)
                                .applicationCardHandCursor()
                                .onTapGesture {
                                    selectedContact = row.contact
                                }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if searchText.isEmpty {
            ContentUnavailableView {
                Label("No Contacts", systemImage: "person.2")
            } description: {
                Text("Create recruiter and interviewer profiles to keep conversations attached to your applications.")
            } actions: {
                Button("Add Contact") {
                    onAddContact()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
        } else {
            ContentUnavailableView.search(text: searchText)
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

private struct ContactCardView: View {
    let row: ContactRow
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(0.14))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Text(row.initials)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.fullName)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let title = row.title, !title.isEmpty {
                        Text(title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    if let relationship = row.relationship, !relationship.isEmpty {
                        Text(relationship)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(row.displayCompanyName, systemImage: "building.2")
                if let email = row.email, !email.isEmpty {
                    Label(email, systemImage: "envelope")
                }
                Text("\(row.linkedCount) linked application\(row.linkedCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isSelected ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.22 : 0.12) : DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }
}
