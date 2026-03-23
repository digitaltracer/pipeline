import SwiftUI
import PipelineKit

struct ApplicationContactsSection: View {
    let application: JobApplication
    var onManageContacts: () -> Void
    var onSelectContact: ((Contact) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Contacts", systemImage: "person.2")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Manage") {
                    onManageContacts()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
                .interactiveHandCursor()
            }

            if application.sortedContactLinks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.title2)
                        .foregroundColor(.secondary.opacity(0.5))

                    Text("No contacts linked")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button {
                        onManageContacts()
                    } label: {
                        Text("Link a Contact")
                            .font(.caption.weight(.medium))
                            .foregroundColor(DesignSystem.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .interactiveHandCursor()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.lg)
                .appCard(elevated: true)
            } else {
                ForEach(application.sortedContactLinks) { link in
                    if let contact = link.contact {
                        Button {
                            onSelectContact?(contact)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(DesignSystem.Colors.accent.opacity(0.14))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Text(contact.initials)
                                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                                            .foregroundColor(DesignSystem.Colors.accent)
                                    }

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(contact.fullName)
                                            .font(.subheadline)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.primary)

                                        if link.isPrimary {
                                            Text("Primary")
                                                .font(.caption2)
                                                .fontWeight(.medium)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(DesignSystem.Colors.accent.opacity(0.12))
                                                .foregroundColor(DesignSystem.Colors.accent)
                                                .clipShape(Capsule())
                                        }
                                    }

                                    Text(link.role.displayName)
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    if let email = contact.email, !email.isEmpty {
                                        Text(email)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .interactiveHandCursor()
                        .appCard(elevated: true)
                    }
                }
            }
        }
    }
}
