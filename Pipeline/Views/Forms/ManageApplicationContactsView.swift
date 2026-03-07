import SwiftUI
import SwiftData
import PipelineKit

struct ManageApplicationContactsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Contact.fullName) private var contacts: [Contact]

    let application: JobApplication
    @State private var selectedContactID: UUID?
    @State private var showingCreateContact = false
    @State private var saveErrorMessage: String?

    private let viewModel = ApplicationDetailViewModel()

    var body: some View {
        NavigationStack {
            Form {
                Section("Linked Contacts") {
                    if application.sortedContactLinks.isEmpty {
                        Text("No contacts linked yet.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(application.sortedContactLinks) { link in
                            linkedContactRow(link)
                        }
                    }
                }

                Section("Link Existing Contact") {
                    Picker("Contact", selection: $selectedContactID) {
                        Text("Select Contact").tag(nil as UUID?)
                        ForEach(availableContacts) { contact in
                            Text(contact.fullName).tag(Optional(contact.id))
                        }
                    }

                    Button("Link to Application") {
                        linkSelectedContact()
                    }
                    .disabled(selectedContactID == nil)
                }

                Section {
                    Button("Create New Contact") {
                        showingCreateContact = true
                    }
                }
            }
            .navigationTitle("Manage Contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 620, idealWidth: 680, minHeight: 520, idealHeight: 560)
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
                    selectedContactID = nil
                } catch {
                    saveErrorMessage = error.localizedDescription
                }
            }
        }
        .alert("Unable to Update Contacts", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var availableContacts: [Contact] {
        contacts.filter { contact in
            !(application.contactLinks ?? []).contains(where: { $0.contact?.id == contact.id })
        }
    }

    @ViewBuilder
    private func linkedContactRow(_ link: ApplicationContactLink) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(link.contact?.fullName ?? "Unknown Contact")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let email = link.contact?.email, !email.isEmpty {
                        Text(email)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if link.isPrimary {
                    Text("Primary")
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(DesignSystem.Colors.accent.opacity(0.12))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .clipShape(Capsule())
                }
            }

            Picker("Role", selection: Binding(
                get: { link.role },
                set: { newRole in updateRole(newRole, for: link) }
            )) {
                ForEach(ContactRole.allCases) { role in
                    Text(role.displayName).tag(role)
                }
            }

            Toggle("Primary Contact", isOn: Binding(
                get: { link.isPrimary },
                set: { newValue in updatePrimaryState(newValue, for: link) }
            ))

            Button("Unlink", role: .destructive) {
                unlink(link)
            }
        }
        .padding(.vertical, 4)
    }

    private func linkSelectedContact() {
        guard let selectedContactID,
              let contact = contacts.first(where: { $0.id == selectedContactID })
        else { return }

        do {
            try viewModel.linkContact(
                contact,
                to: application,
                role: .recruiter,
                markPrimary: application.primaryContactLink == nil,
                context: modelContext
            )
            self.selectedContactID = nil
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
