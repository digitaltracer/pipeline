import SwiftUI
import SwiftData
import PipelineKit

struct ContactEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    let contactToEdit: Contact?
    var defaultCompanyName: String? = nil
    var onSave: ((Contact) -> Void)? = nil

    @State private var fullName: String
    @State private var email: String
    @State private var phone: String
    @State private var companyName: String
    @State private var title: String
    @State private var relationship: String
    @State private var linkedInURL: String
    @State private var notes: String
    @State private var saveErrorMessage: String?

    init(
        contactToEdit: Contact? = nil,
        defaultCompanyName: String? = nil,
        onSave: ((Contact) -> Void)? = nil
    ) {
        self.contactToEdit = contactToEdit
        self.defaultCompanyName = defaultCompanyName
        self.onSave = onSave
        _fullName = State(initialValue: contactToEdit?.fullName ?? "")
        _email = State(initialValue: contactToEdit?.email ?? "")
        _phone = State(initialValue: contactToEdit?.phone ?? "")
        _companyName = State(initialValue: contactToEdit?.companyName ?? defaultCompanyName ?? "")
        _title = State(initialValue: contactToEdit?.title ?? "")
        _relationship = State(initialValue: contactToEdit?.relationship ?? "")
        _linkedInURL = State(initialValue: contactToEdit?.linkedInURL ?? "")
        _notes = State(initialValue: contactToEdit?.notes ?? "")
    }

    private var isEditing: Bool { contactToEdit != nil }

    private var normalizedName: String {
        fullName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedCompanyName: String {
        companyName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedRelationship: String {
        relationship.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedLinkedInURL: String {
        linkedInURL.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailValidationMessage: String? {
        guard !normalizedEmail.isEmpty else { return nil }
        return Self.looksLikeValidEmail(normalizedEmail) ? nil : "Enter a valid email address"
    }

    private var isFormValid: Bool {
        !normalizedName.isEmpty && emailValidationMessage == nil
    }

    private var initials: String {
        let words = normalizedName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap { $0.first.map(String.init) }
        let joined = words.joined().uppercased()
        if !joined.isEmpty { return joined }
        if let first = normalizedName.first { return String(first).uppercased() }
        return "?"
    }

    var body: some View {
        Group {
            #if os(macOS)
            macOSBody
            #else
            iOSBody
            #endif
        }
        .alert("Unable to Save Contact", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    #if os(macOS)
    private var macOSBody: some View {
        VStack(spacing: 0) {
            header

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    profileHero

                    HStack(alignment: .top, spacing: 16) {
                        identityCard
                        contactCard
                    }

                    notesCard
                }
                .padding(24)
            }

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            footer
        }
        .frame(width: 760, height: 620)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isEditing ? "Edit Contact" : "New Contact")
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(isEditing ? "Refresh this person’s profile and communication details." : "Create a polished contact profile for recruiters, interviewers, and referrals.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

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
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var profileHero: some View {
        HStack(spacing: 18) {
            Circle()
                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.3 : 0.14))
                .frame(width: 78, height: 78)
                .overlay {
                    Text(initials)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(DesignSystem.Colors.accent)
                }

            VStack(alignment: .leading, spacing: 8) {
                Text(normalizedName.isEmpty ? "Contact Name" : normalizedName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(normalizedName.isEmpty ? .secondary : .primary)

                HStack(spacing: 8) {
                    ContactPill(
                        title: normalizedTitle.isEmpty ? "Role / Title" : normalizedTitle,
                        icon: "briefcase"
                    )

                ContactPill(
                    title: normalizedCompanyName.isEmpty ? "Company" : normalizedCompanyName,
                    icon: "building.2"
                )

                if !normalizedRelationship.isEmpty {
                    ContactPill(
                        title: normalizedRelationship,
                        icon: "person.crop.circle.badge.checkmark"
                    )
                }
            }

                Text(normalizedName.isEmpty ? "A complete profile helps you link emails, calls, interviews, and notes back to the right person." : "This profile will appear across linked applications and timeline entries.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(22)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private var identityCard: some View {
        ContactFormCard(
            title: "Identity",
            subtitle: "Core details you’ll recognize at a glance.",
            icon: "person.text.rectangle"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ContactField(label: "Full Name *", placeholder: "Avery Chen", text: $fullName)
                ContactField(label: "Role / Title", placeholder: "Senior Recruiter", text: $title)
                ContactField(label: "Company", placeholder: "OpenAI", text: $companyName)
                ContactField(label: "Relationship", placeholder: "Former teammate", text: $relationship)
            }
        }
    }

    private var contactCard: some View {
        ContactFormCard(
            title: "Reach",
            subtitle: "How you actually get back to this person.",
            icon: "bubble.left.and.text.bubble.right"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                ContactField(
                    label: "Email",
                    placeholder: "avery@company.com",
                    text: $email,
                    validationMessage: emailValidationMessage
                )
                ContactField(label: "Phone", placeholder: "+1 (555) 123-4567", text: $phone)
                ContactField(label: "LinkedIn URL", placeholder: "https://linkedin.com/in/avery", text: $linkedInURL)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Quality")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        ContactQualityBadge(
                            title: normalizedName.isEmpty ? "Missing name" : "Named",
                            isActive: !normalizedName.isEmpty
                        )
                        ContactQualityBadge(
                            title: normalizedEmail.isEmpty ? "No email" : (emailValidationMessage == nil ? "Email" : "Check email"),
                            isActive: !normalizedEmail.isEmpty && emailValidationMessage == nil
                        )
                        ContactQualityBadge(
                            title: phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "No phone" : "Phone",
                            isActive: !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )
                    }
                }
            }
        }
    }

    private var notesCard: some View {
        ContactFormCard(
            title: "Context",
            subtitle: "Capture rapport, responsibilities, and follow-up context.",
            icon: "note.text"
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ZStack(alignment: .topLeading) {
                    if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Shared timeline, hiring team context, communication preferences, or anything worth remembering before your next follow-up.")
                            .font(.body)
                            .foregroundColor(DesignSystem.Colors.placeholder(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $notes)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .frame(minHeight: 170)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .fill(DesignSystem.Colors.inputBackground(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let footerValidationMessage {
                Label(footerValidationMessage, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundColor(footerValidationMessage == "Full name is required" ? .secondary : .orange)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)

            Button(isEditing ? "Save Contact" : "Create Contact") {
                saveContact()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .disabled(!isFormValid)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
    #endif

    private var iOSBody: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Circle()
                            .fill(DesignSystem.Colors.accent.opacity(0.14))
                            .frame(width: 58, height: 58)
                            .overlay {
                                Text(initials)
                                    .font(.system(size: 22, weight: .bold, design: .rounded))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(normalizedName.isEmpty ? "Contact Name" : normalizedName)
                                .font(.headline)
                                .foregroundColor(normalizedName.isEmpty ? .secondary : .primary)
                            Text(normalizedTitle.isEmpty ? "Role / Title" : normalizedTitle)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(normalizedCompanyName.isEmpty ? "Company" : normalizedCompanyName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Identity") {
                    TextField("Full Name", text: $fullName)
                    TextField("Role / Title", text: $title)
                    TextField("Company", text: $companyName)
                    TextField("Relationship", text: $relationship)
                }

                Section("Reach") {
                    emailField
                    if let emailValidationMessage {
                        Text(emailValidationMessage)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    phoneField
                    #if os(iOS)
                    TextField("LinkedIn URL", text: $linkedInURL)
                        .textInputAutocapitalization(.never)
                    #else
                    TextField("LinkedIn URL", text: $linkedInURL)
                    #endif
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create") {
                        saveContact()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private func saveContact() {
        guard !normalizedName.isEmpty else {
            saveErrorMessage = "Name is required."
            return
        }

        guard emailValidationMessage == nil else {
            saveErrorMessage = "Please enter a valid email address or leave the field empty."
            return
        }

        let normalizedPhone = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        let contact: Contact
        if let contactToEdit {
            contact = contactToEdit
        } else {
            contact = Contact(fullName: normalizedName)
            modelContext.insert(contact)
        }

        contact.fullName = normalizedName
        contact.email = normalizedEmail.isEmpty ? nil : normalizedEmail
        contact.phone = normalizedPhone.isEmpty ? nil : normalizedPhone
        contact.companyName = normalizedCompanyName.isEmpty ? nil : normalizedCompanyName
        contact.title = normalizedTitle.isEmpty ? nil : normalizedTitle
        contact.relationship = normalizedRelationship.isEmpty ? nil : normalizedRelationship
        contact.linkedInURL = normalizedLinkedInURL.isEmpty ? nil : URLHelpers.normalize(normalizedLinkedInURL)
        contact.notes = normalizedNotes.isEmpty ? nil : normalizedNotes
        contact.updateTimestamp()

        do {
            try modelContext.save()
            onSave?(contact)
            dismiss()
        } catch {
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
        }
    }

    private var footerValidationMessage: String? {
        if normalizedName.isEmpty {
            return "Full name is required"
        }
        return emailValidationMessage
    }

    @ViewBuilder
    private var emailField: some View {
        #if os(iOS)
        TextField("Email", text: $email)
            .keyboardType(.emailAddress)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        #else
        TextField("Email", text: $email)
        #endif
    }

    @ViewBuilder
    private var phoneField: some View {
        #if os(iOS)
        TextField("Phone", text: $phone)
            .keyboardType(.phonePad)
        #else
        TextField("Phone", text: $phone)
        #endif
    }

    private static func looksLikeValidEmail(_ value: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return value.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

#if os(macOS)
private struct ContactFormCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}

private struct ContactField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var validationMessage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("", text: $text, prompt: Text(placeholder))
                .textFieldStyle(.plain)
                .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
                .appInput()

            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }
}

private struct ContactPill: View {
    let title: String
    let icon: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .lineLimit(1)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            Capsule()
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }
}

private struct ContactQualityBadge: View {
    let title: String
    let isActive: Bool

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundColor(isActive ? DesignSystem.Colors.accent : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isActive ? DesignSystem.Colors.accent.opacity(0.12) : Color.secondary.opacity(0.10))
            )
    }
}
#endif
