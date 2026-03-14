import SwiftUI
import SwiftData
import PipelineKit

struct ContactDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var contact: Contact
    var onClose: (() -> Void)? = nil
    var onSelectApplication: ((JobApplication) -> Void)? = nil

    @State private var showingEditor = false
    @State private var showingDeleteAlert = false
    @State private var actionErrorMessage: String?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    profileSection
                    linkedApplicationsSection
                    contactTimelineSection
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .sheet(isPresented: $showingEditor) {
            ContactEditorView(contactToEdit: contact)
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteContact()
            }
        } message: {
            Text("Delete this contact and unlink it from all applications? Existing activity entries will keep their notes but lose the person reference.")
        }
        .alert("Action Failed", isPresented: Binding(
            get: { actionErrorMessage != nil },
            set: { if !$0 { actionErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Circle()
                .fill(DesignSystem.Colors.accent.opacity(0.14))
                .frame(width: 54, height: 54)
                .overlay {
                    Text(contact.initials)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(contact.fullName)
                    .font(.title3)
                    .fontWeight(.bold)

                if let title = contact.title, !title.isEmpty {
                    Text(title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Text(contact.displayCompanyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    showingEditor = true
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
                .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                .clipShape(Circle())

                Button(role: .destructive) {
                    showingDeleteAlert = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundColor(.red.opacity(0.9))
                .background(DesignSystem.Colors.surfaceElevated(colorScheme))
                .clipShape(Circle())

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

    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Profile", systemImage: "person.crop.circle")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                detailCard(label: "Email", value: contact.email ?? "—", icon: "envelope")
                detailCard(label: "Phone", value: contact.phone ?? "—", icon: "phone")
                detailCard(label: "Company", value: contact.companyName ?? "—", icon: "building.2")
                detailCard(label: "Role", value: contact.title ?? "—", icon: "briefcase")
                detailCard(label: "Relationship", value: contact.relationship ?? "—", icon: "person.2")
                detailCard(label: "LinkedIn", value: contact.linkedInURL ?? "—", icon: "link")
            }

            if let notes = contact.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
    }

    private var linkedApplicationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Linked Applications", systemImage: "briefcase")
                .font(.headline)

            if contact.linkedApplications.isEmpty {
                Text("This contact is not linked to any applications yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard(cornerRadius: 14, elevated: true, shadow: false)
            } else {
                ForEach(contact.linkedApplications) { application in
                    Button {
                        onSelectApplication?(application)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(application.role)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)

                                Text(application.companyName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            StatusBadge(status: application.status, showIcon: true)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .appCard(cornerRadius: 14, elevated: true, shadow: false)
                }
            }
        }
    }

    private var contactTimelineSection: some View {
        ApplicationTimelineView(
            activities: contact.sortedActivities,
            emptyTitle: "No related activity yet",
            emptyDescription: "When this person appears in interviews, emails, or calls, the entries will show up here."
        )
    }

    private func detailCard(label: String, value: String, icon: String) -> some View {
        DetailInfoCard(label: label, value: value, icon: icon, iconColor: DesignSystem.Colors.accent)
    }

    private func deleteContact() {
        modelContext.delete(contact)
        do {
            try modelContext.save()
            onClose?()
        } catch {
            modelContext.rollback()
            actionErrorMessage = error.localizedDescription
        }
    }
}
