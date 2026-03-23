import SwiftUI
import SwiftData
import PipelineKit

struct ActivityEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Contact.fullName) private var contacts: [Contact]

    let application: JobApplication
    let activityToEdit: ApplicationActivity?
    let defaultKind: ApplicationActivityKind

    @State private var selectedKind: ApplicationActivityKind
    @State private var occurredAt: Date
    @State private var selectedContactID: UUID?
    @State private var interviewStage: InterviewStage
    @State private var scheduledDurationMinutes: Int
    @State private var rating: Int
    @State private var emailSubject: String
    @State private var emailBodySnapshot: String
    @State private var notes: String
    @State private var saveErrorMessage: String?
    @FocusState private var focusedEditor: EditorField?

    private let viewModel = ApplicationDetailViewModel()

    private enum EditorField: Hashable {
        case emailBody
        case notes
    }

    init(
        application: JobApplication,
        activityToEdit: ApplicationActivity? = nil,
        defaultKind: ApplicationActivityKind = .note
    ) {
        self.application = application
        self.activityToEdit = activityToEdit
        self.defaultKind = defaultKind
        _selectedKind = State(initialValue: activityToEdit?.kind ?? defaultKind)
        _occurredAt = State(initialValue: activityToEdit?.occurredAt ?? Date())
        _selectedContactID = State(initialValue: activityToEdit?.contact?.id)
        _interviewStage = State(initialValue: activityToEdit?.interviewStage ?? .phoneScreen)
        _scheduledDurationMinutes = State(initialValue: activityToEdit?.scheduledDurationMinutes ?? 60)
        _rating = State(initialValue: activityToEdit?.rating ?? 3)
        _emailSubject = State(initialValue: activityToEdit?.emailSubject ?? "")
        _emailBodySnapshot = State(initialValue: activityToEdit?.emailBodySnapshot ?? "")
        _notes = State(initialValue: activityToEdit?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            VStack(spacing: 0) {
                macHeader

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                ScrollView {
                    modalContent
                        .padding(24)
                }

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                macFooter
            }
            .frame(minWidth: 760, idealWidth: 820, minHeight: 650, idealHeight: 720)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
            #else
            ScrollView {
                modalContent
                    .padding(16)
            }
            .background(DesignSystem.Colors.contentBackground(colorScheme).ignoresSafeArea())
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(primaryActionTitle) {
                        saveActivity()
                    }
                }
            }
            #endif
        }
        .alert("Unable to Save Activity", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "An unknown error occurred.")
        }
    }

    private var modalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            overviewCard
            activityTypeCard

            if selectedKind == .interview {
                interviewCard
            }

            if selectedKind == .email {
                emailCard
            }

            notesCard
        }
    }

    private var overviewCard: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(selectedKind.color.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 58, height: 58)

                Image(systemName: selectedKind.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(selectedKind.color)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(navigationTitle)
                        .font(.title3.weight(.semibold))

                    Text(selectedKind.displayName.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.8)
                        .foregroundColor(selectedKind.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(selectedKind.color.opacity(colorScheme == .dark ? 0.16 : 0.10))
                        )
                }

                Text(applicationContextLine)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)

                Text(kindSummaryText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private var activityTypeCard: some View {
        sectionCard(
            title: "Activity Setup",
            icon: "square.grid.2x2",
            description: "Choose the activity type and the core metadata that should appear in the timeline."
        ) {
            LazyVGrid(columns: kindGridColumns, spacing: 12) {
                ForEach(ApplicationActivityKind.manualCases) { kind in
                    activityKindButton(for: kind)
                }
            }

            Divider()

            LazyVGrid(columns: detailGridColumns, spacing: 14) {
                fieldSurface(
                    title: selectedKind == .interview ? "Interview Start" : "Occurred At",
                    caption: timeFieldCaption
                ) {
                    DatePicker(
                        "",
                        selection: $occurredAt,
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    #if os(macOS)
                    .datePickerStyle(.compact)
                    #endif
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }

                fieldSurface(
                    title: "Contact",
                    caption: "Optional. Associate the activity with a specific person."
                ) {
                    Picker("", selection: $selectedContactID) {
                        Text("No Contact").tag(nil as UUID?)
                        ForEach(suggestedContacts) { contact in
                            Text(contact.fullName).tag(Optional(contact.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }
            }
        }
    }

    private var interviewCard: some View {
        sectionCard(
            title: "Interview Details",
            icon: "person.2.wave.2",
            description: "Capture the interview stage, expected duration, and your overall readout."
        ) {
            LazyVGrid(columns: detailGridColumns, spacing: 14) {
                fieldSurface(title: "Stage", caption: "Use the round that best reflects the interview.") {
                    Picker("", selection: $interviewStage) {
                        ForEach(InterviewStage.allCases) { stage in
                            Text(stage.displayName).tag(stage)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }

                fieldSurface(title: "Duration", caption: "Scheduled length for reminders and timeline context.") {
                    Picker("", selection: $scheduledDurationMinutes) {
                        ForEach(durationOptions, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }
            }

            fieldSurface(title: "Rating", caption: ratingDescription) {
                HStack(spacing: 10) {
                    ForEach(1 ... 5, id: \.self) { value in
                        ratingButton(for: value)
                    }
                }
            }

            banner(
                text: interviewTimingHelperText,
                systemImage: occurredAt > Date() ? "calendar.badge.clock" : "lightbulb",
                tint: .orange
            )
        }
    }

    private var emailCard: some View {
        sectionCard(
            title: "Email Snapshot",
            icon: "envelope.badge",
            description: "Store the important parts of the message so the timeline stays useful later."
        ) {
            fieldSurface(title: "Subject") {
                TextField("Subject line", text: $emailSubject)
                    .textFieldStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
            }

            editorSurface(
                title: "Email Body",
                caption: "Paste the sent message or summarize the key points.",
                text: $emailBodySnapshot,
                placeholder: "Paste the message body or capture the important parts of the conversation.",
                focusedField: .emailBody,
                minHeight: 170
            )
        }
    }

    private var notesCard: some View {
        sectionCard(
            title: selectedKind == .email ? "Internal Notes" : "Details",
            icon: "text.justify.left",
            description: notesSectionDescription
        ) {
            editorSurface(
                title: selectedKind == .email ? "Notes" : "Activity Notes",
                caption: "What should Future You see when scanning the timeline?",
                text: $notes,
                placeholder: notesPlaceholder,
                focusedField: .notes,
                minHeight: selectedKind == .email ? 150 : 190
            )
        }
    }

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(navigationTitle)
                    .font(.title3.weight(.semibold))

                Text("Timeline activity for \(applicationContextLine)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var macFooter: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    .foregroundColor(selectedKind.color)

                Text(footerMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)

            Button(primaryActionTitle) {
                saveActivity()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(DesignSystem.Colors.surfaceElevated(colorScheme))
    }
    #endif

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func fieldSurface<Content: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(.secondary)

            content()

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func editorSurface(
        title: String,
        caption: String,
        text: Binding<String>,
        placeholder: String,
        focusedField: EditorField,
        minHeight: CGFloat
    ) -> some View {
        fieldSurface(title: title, caption: caption) {
            ZStack(alignment: .topLeading) {
                if text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   self.focusedEditor != focusedField {
                    Text(placeholder)
                        .font(.body)
                        .foregroundColor(DesignSystem.Colors.placeholder(colorScheme))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .allowsHitTesting(false)
                }

                TextEditor(text: text)
                    .font(.body)
                    .focused($focusedEditor, equals: focusedField)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minHeight: minHeight)
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

    private func activityKindButton(for kind: ApplicationActivityKind) -> some View {
        let isSelected = selectedKind == kind

        return Button {
            selectedKind = kind
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: kind.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(isSelected ? kind.color : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)

                    Text(activityTypeSubtitle(for: kind))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? kind.color.opacity(colorScheme == .dark ? 0.18 : 0.10)
                            : DesignSystem.Colors.surfaceElevated(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? kind.color : DesignSystem.Colors.stroke(colorScheme),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func ratingButton(for value: Int) -> some View {
        let isSelected = rating == value

        return Button {
            rating = value
        } label: {
            VStack(spacing: 8) {
                Image(systemName: isSelected ? "star.fill" : "star")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(isSelected ? .orange : .secondary)

                Text("\(value)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.10)
                            : DesignSystem.Colors.inputBackground(colorScheme)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        isSelected ? Color.orange : DesignSystem.Colors.stroke(colorScheme),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
                .padding(.top, 2)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.08))
        )
    }

    private var suggestedContacts: [Contact] {
        let linkedContacts = application.sortedContactLinks.compactMap(\.contact)
        let unlinkedContacts = contacts.filter { contact in
            !linkedContacts.contains(where: { $0.id == contact.id })
        }
        return linkedContacts + unlinkedContacts
    }

    private var navigationTitle: String {
        activityToEdit == nil ? "New Activity" : "Edit Activity"
    }

    private var primaryActionTitle: String {
        activityToEdit == nil ? "Save Activity" : "Update Activity"
    }

    private var applicationContextLine: String {
        "\(application.companyName) · \(application.role)"
    }

    private var kindSummaryText: String {
        switch selectedKind {
        case .interview:
            return "Track the interview event, stage, timing, and outcome in one structured timeline entry."
        case .email:
            return "Capture the message context and preserve a searchable snapshot of the conversation."
        case .call:
            return "Log the call, the person involved, and the outcome so follow-up stays grounded."
        case .text:
            return "Record short-form outreach or recruiter updates without losing the timeline context."
        case .note:
            return "Add a general note for anything important that does not fit another interaction type."
        case .statusChange:
            return "System-generated status changes are recorded automatically."
        case .followUp:
            return "System-generated follow-up steps are recorded automatically."
        }
    }

    private var notesSectionDescription: String {
        selectedKind == .email
            ? "Keep internal context separate from the email snapshot so the timeline stays readable."
            : "Capture the important outcome, context, and next step so this activity is useful later."
    }

    private var notesPlaceholder: String {
        switch selectedKind {
        case .interview:
            return "Summarize what happened, who attended, how it went, and what happens next."
        case .email:
            return "Add private notes, decisions, or follow-up context that should not live in the email snapshot."
        case .call, .text:
            return "Capture the key points, commitments, blockers, and any next step from the conversation."
        case .note:
            return "Write down anything important you want to preserve on the application timeline."
        case .statusChange, .followUp:
            return "Add supporting detail for this timeline entry."
        }
    }

    private var footerMessage: String {
        selectedKind == .interview
            ? interviewTimingHelperText
            : "This activity will be saved to the application timeline and used throughout Pipeline."
    }

    private var timeFieldCaption: String {
        selectedKind == .interview
            ? "Future interviews will trigger reminder logic after the scheduled end time."
            : "Choose when the activity actually happened so the timeline stays accurate."
    }

    private var durationOptions: [Int] {
        [15, 30, 45, 60, 90, 120, 180, 240]
    }

    private var ratingDescription: String {
        switch rating {
        case 1: return "Went poorly. Strong concerns or clear mismatch."
        case 2: return "Below expectations. Some notable issues came up."
        case 3: return "Average. Mostly neutral outcome."
        case 4: return "Strong conversation. Positive signals overall."
        case 5: return "Excellent. High confidence and clear momentum."
        default: return ""
        }
    }

    #if os(macOS)
    private var kindGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var detailGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 14, alignment: .top),
            GridItem(.flexible(), spacing: 14, alignment: .top)
        ]
    }
    #else
    private var kindGridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    private var detailGridColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 14, alignment: .top)]
    }
    #endif

    private func activityTypeSubtitle(for kind: ApplicationActivityKind) -> String {
        switch kind {
        case .interview:
            return "Structured feedback, timing, and stage tracking"
        case .email:
            return "Message snapshot and follow-up context"
        case .call:
            return "Phone conversation and outcome"
        case .text:
            return "Short-form messaging updates"
        case .note:
            return "General timeline note"
        case .statusChange:
            return "Automatic workflow transition"
        case .followUp:
            return "Automatic follow-up reminder"
        }
    }

    private func saveActivity() {
        do {
            try viewModel.saveActivity(
                activityToEdit,
                kind: selectedKind,
                occurredAt: occurredAt,
                notes: normalized(notes),
                contact: selectedContactID.flatMap { id in
                    contacts.first(where: { $0.id == id })
                },
                interviewStage: selectedKind == .interview ? interviewStage : nil,
                scheduledDurationMinutes: selectedKind == .interview ? scheduledDurationMinutes : nil,
                rating: selectedKind == .interview ? rating : nil,
                emailSubject: selectedKind == .email ? normalized(emailSubject) : nil,
                emailBodySnapshot: selectedKind == .email ? normalized(emailBodySnapshot) : nil,
                for: application,
                context: modelContext
            )
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var interviewTimingHelperText: String {
        if occurredAt > Date() {
            let endDate = Calendar.current.date(
                byAdding: .minute,
                value: scheduledDurationMinutes,
                to: occurredAt
            ) ?? occurredAt
            return "This interview is scheduled. Pipeline will remind you to debrief 30 minutes after \(endDate.formatted(date: .omitted, time: .shortened))."
        }

        return "If you log interviews in advance here, Pipeline can schedule the debrief reminder after they end."
    }
}
