import SwiftUI
import SwiftData
import PipelineKit

struct ManageApplicationContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Contact.fullName) private var contacts: [Contact]

    let application: JobApplication
    @State private var showingCreateContact = false
    @State private var saveErrorMessage: String?
    @State private var linkToUnlink: ApplicationContactLink?
    @State private var contactToEdit: Contact?

    private let viewModel = ApplicationDetailViewModel()

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            iOSBody
            #endif
        }
        .sheet(isPresented: $showingCreateContact) {
            ContactEditorView(defaultCompanyName: application.companyName) { contact in
                do {
                    try viewModel.linkContact(
                        contact,
                        to: application,
                        role: .recruiter,
                        markPrimary: application.primaryContactLink == nil,
                        context: modelContext
                    )
                } catch {
                    saveErrorMessage = error.localizedDescription
                }
            }
        }
        .sheet(item: $contactToEdit) { contact in
            ContactEditorView(contactToEdit: contact)
        }
        .alert("Unable to Update Contacts", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
        .confirmationDialog(
            "Unlink Contact",
            isPresented: Binding(
                get: { linkToUnlink != nil },
                set: { if !$0 { linkToUnlink = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Unlink", role: .destructive) {
                if let link = linkToUnlink {
                    unlink(link)
                    linkToUnlink = nil
                }
            }
            Button("Cancel", role: .cancel) {
                linkToUnlink = nil
            }
        } message: {
            Text("This contact will be removed from this application. You can re-link them later.")
        }
    }

    // MARK: - macOS Layout

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if application.sortedContactLinks.isEmpty {
                        emptyState
                    } else {
                        ForEach(application.sortedContactLinks) { link in
                            linkedContactCard(link)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.lg)
            }

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            footer
        }
        .frame(width: 620, height: 520)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }
    #endif

    // MARK: - iOS Layout

    private var iOSBody: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if application.sortedContactLinks.isEmpty {
                        emptyState
                    } else {
                        ForEach(application.sortedContactLinks) { link in
                            linkedContactCard(link)
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .navigationTitle("Manage Contacts")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    addMenu
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Manage Contacts")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text("Link recruiters, interviewers, and referrals to this application.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                addMenu

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                        .foregroundColor(.secondary)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }

    // MARK: - Add Menu

    private var addMenu: some View {
        Menu {
            Button {
                showingCreateContact = true
            } label: {
                Label("Create New Contact", systemImage: "plus.circle")
            }

            if !availableContacts.isEmpty {
                Divider()

                Menu("Link Existing Contact") {
                    ForEach(availableContacts) { contact in
                        Button {
                            linkContact(contact)
                        } label: {
                            Label {
                                VStack(alignment: .leading) {
                                    Text(contact.fullName)
                                    if let company = contact.companyName, !company.isEmpty {
                                        Text(company)
                                    }
                                }
                            } icon: {
                                Image(systemName: "person.crop.circle")
                            }
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .foregroundColor(DesignSystem.Colors.accent)
                .background(DesignSystem.Colors.accent.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundColor(.secondary.opacity(0.4))

            Text("No contacts linked")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Add recruiters, hiring managers, or referrals to keep track of who you're talking to.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)

            HStack(spacing: 12) {
                Button {
                    showingCreateContact = true
                } label: {
                    Label("Create Contact", systemImage: "plus.circle")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)

                if !availableContacts.isEmpty {
                    Menu {
                        ForEach(availableContacts) { contact in
                            Button(contact.fullName) {
                                linkContact(contact)
                            }
                        }
                    } label: {
                        Label("Link Existing", systemImage: "link.badge.plus")
                            .font(.subheadline.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.xl)
        .appCard(elevated: true)
    }

    // MARK: - Linked Contact Card

    @ViewBuilder
    private func linkedContactCard(_ link: ApplicationContactLink) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // ── Profile Header ──
            HStack(spacing: 14) {
                Circle()
                    .fill(link.role.color.opacity(0.14))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Text(link.contact?.initials ?? "?")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundColor(link.role.color)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(link.contact?.fullName ?? "Unknown Contact")
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

                    HStack(spacing: 6) {
                        if let title = link.contact?.title, !title.isEmpty {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        if let title = link.contact?.title, !title.isEmpty,
                           let company = link.contact?.companyName, !company.isEmpty {
                            Text("·")
                                .font(.caption)
                                .foregroundColor(.secondary.opacity(0.5))
                        }

                        if let company = link.contact?.companyName, !company.isEmpty {
                            Text(company)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Role badge
                HStack(spacing: 5) {
                    Image(systemName: link.role.icon)
                        .font(.system(size: 10, weight: .semibold))
                    Text(link.role.displayName)
                        .font(.caption2)
                        .fontWeight(.medium)
                }
                .foregroundColor(link.role.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(link.role.color.opacity(0.1))
                .clipShape(Capsule())
            }
            .padding(DesignSystem.Spacing.md)

            // ── Detail Grid ──
            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                DetailInfoCard(
                    label: "Email",
                    value: link.contact?.email ?? "—",
                    icon: "envelope",
                    iconColor: DesignSystem.Colors.accent
                )
                DetailInfoCard(
                    label: "Phone",
                    value: link.contact?.phone ?? "—",
                    icon: "phone",
                    iconColor: DesignSystem.Colors.accent
                )
                DetailInfoCard(
                    label: "LinkedIn",
                    value: link.contact?.linkedInURL != nil ? "Profile" : "—",
                    icon: "link",
                    iconColor: DesignSystem.Colors.accent
                )
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.bottom, 12)

            Divider()

            // ── Actions Row ──
            HStack(spacing: DesignSystem.Spacing.md) {
                // Role picker
                HStack(spacing: 6) {
                    Image(systemName: link.role.icon)
                        .font(.caption)
                        .foregroundColor(link.role.color)

                    Picker("Role", selection: Binding(
                        get: { link.role },
                        set: { newRole in updateRole(newRole, for: link) }
                    )) {
                        ForEach(ContactRole.allCases) { role in
                            Label(role.displayName, systemImage: role.icon).tag(role)
                        }
                    }
                    .labelsHidden()
                    #if os(macOS)
                    .pickerStyle(.menu)
                    #endif
                    .fixedSize()
                }

                Spacer()

                // Primary toggle
                Button {
                    updatePrimaryState(!link.isPrimary, for: link)
                } label: {
                    Image(systemName: link.isPrimary ? "star.fill" : "star")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(link.isPrimary ? .orange : .secondary)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .interactiveHandCursor()
                .help(link.isPrimary ? "Remove primary status" : "Set as primary contact")

                // Edit
                Button {
                    contactToEdit = link.contact
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .interactiveHandCursor()
                .help("Edit contact details")

                // Unlink
                Button {
                    linkToUnlink = link
                } label: {
                    Image(systemName: "link.badge.minus")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .interactiveHandCursor()
                .help("Unlink from this application")
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, 10)
        }
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    // MARK: - Helpers

    private var availableContacts: [Contact] {
        contacts.filter { contact in
            !(application.contactLinks ?? []).contains(where: { $0.contact?.id == contact.id })
        }
    }

    private func linkContact(_ contact: Contact) {
        do {
            try viewModel.linkContact(
                contact,
                to: application,
                role: .recruiter,
                markPrimary: application.primaryContactLink == nil,
                context: modelContext
            )
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func updateRole(_ role: ContactRole, for link: ApplicationContactLink) {
        do {
            try viewModel.updateContactLink(link, role: role, isPrimary: link.isPrimary, in: application, context: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func updatePrimaryState(_ isPrimary: Bool, for link: ApplicationContactLink) {
        do {
            try viewModel.updateContactLink(link, role: link.role, isPrimary: isPrimary, in: application, context: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func unlink(_ link: ApplicationContactLink) {
        do {
            try viewModel.unlinkContact(link, from: application, context: modelContext)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}
