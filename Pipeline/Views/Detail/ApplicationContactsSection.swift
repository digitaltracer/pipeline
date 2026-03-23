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
                    .font(.headline)

                Spacer()

                Button("Manage") {
                    onManageContacts()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
                .interactiveHandCursor()
            }

            if application.sortedContactLinks.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)

                    Text("No contacts linked")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Button("Link a Contact") {
                        onManageContacts()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .interactiveHandCursor()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
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
                        .appCard(cornerRadius: 14, elevated: true, shadow: false)
                    }
                }
            }
        }
    }
}
