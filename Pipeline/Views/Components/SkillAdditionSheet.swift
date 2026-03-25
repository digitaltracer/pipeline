import SwiftUI
import SwiftData
import PipelineKit

struct SkillAdditionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: SkillAdditionViewModel
    @State private var showExistingBullets = false

    let prefilledSkill: String
    let onComplete: ([ResumePatch], SkillAdditionScope) -> Void

    init(
        resumeJSON: String,
        application: JobApplication? = nil,
        settingsViewModel: SettingsViewModel,
        prefilledSkill: String = "",
        missingSkills: [String] = [],
        onComplete: @escaping ([ResumePatch], SkillAdditionScope) -> Void
    ) {
        self.prefilledSkill = prefilledSkill
        _viewModel = State(initialValue: SkillAdditionViewModel(
            resumeJSON: resumeJSON,
            application: application,
            settingsViewModel: settingsViewModel,
            prefilledSkill: prefilledSkill,
            missingSkills: missingSkills
        ))
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            stepContent
            Divider()
            footerBar
        }
        #if os(macOS)
        .frame(width: 560, height: 520)
        #endif
        .onAppear {
            viewModel.setModelContext(modelContext)
            // Apply prefilled skill on appear in case @State init missed it
            let trimmed = prefilledSkill.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                viewModel.skillName = trimmed
                viewModel.currentStep = 1
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("Add Skill Evidence")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .interactiveHandCursor()
            }

            stepIndicator
        }
        .padding(DesignSystem.Spacing.md)
    }

    private var stepIndicator: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(0..<3) { step in
                HStack(spacing: 4) {
                    Circle()
                        .fill(step <= viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(stepLabel(step))
                        .font(.caption2.weight(step == viewModel.currentStep ? .semibold : .regular))
                        .foregroundColor(step <= viewModel.currentStep ? .primary : .secondary)
                }
                if step < 2 {
                    Rectangle()
                        .fill(step < viewModel.currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 1)
                }
            }
        }
    }

    private func stepLabel(_ step: Int) -> String {
        switch step {
        case 0: return "Skill"
        case 1: return "Evidence"
        case 2: return "Category"
        default: return ""
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    switch viewModel.currentStep {
                    case 0: step1SkillName
                    case 1: step2LinkExperience
                    case 2: step3CategoryAndScope
                    default: EmptyView()
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .onChange(of: viewModel.selectedExperienceIndex) {
                withAnimation {
                    proxy.scrollTo("bulletEditor", anchor: .top)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    // MARK: - Step 1: Skill Name

    private var step1SkillName: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("What skill or experience are you adding?")
                .font(.subheadline.weight(.semibold))

            TextField("e.g. Kubernetes, React, Project Management", text: $viewModel.skillName)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    if viewModel.isStep1Valid { viewModel.currentStep = 1 }
                }

            if !viewModel.missingSkills.isEmpty {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Suggested from job gaps:")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    gapSuggestionChips
                }
            }

            if let existing = viewModel.existingCategoryForSkill {
                Label("This skill already exists under \"\(existing)\".", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var gapSuggestionChips: some View {
        let skills = Array(viewModel.missingSkills.prefix(8))
        let rows = skills.chunked(into: 3)
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 6) {
                    ForEach(rows[rowIndex], id: \.self) { skill in
                        Button(skill) {
                            viewModel.skillName = skill
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(Color.orange.opacity(0.12))
                        )
                        .buttonStyle(.plain)
                        .interactiveHandCursor()
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Step 2: Link to Experience

    private var step2LinkExperience: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            Text("Where in your background does \"\(viewModel.trimmedSkillName)\" apply?")
                .font(.subheadline.weight(.semibold))

            if !viewModel.hasExperienceEntries {
                Label("Your resume has no experience entries. Add at least one in the resume editor first.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                experienceList
                if viewModel.selectedExperienceIndex != nil {
                    bulletEditor
                        .id("bulletEditor")
                }
            }
        }
    }

    private var experienceList: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            ForEach(Array(viewModel.schema.experience.enumerated()), id: \.offset) { index, entry in
                Button {
                    viewModel.selectedExperienceIndex = index
                } label: {
                    HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: viewModel.selectedExperienceIndex == index
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(viewModel.selectedExperienceIndex == index ? .accentColor : .secondary)
                            .font(.body)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.primary)
                            Text("\(entry.company) • \(entry.dates)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if !entry.location.isEmpty {
                                Text(entry.location)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()
                    }
                    .padding(DesignSystem.Spacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.cardSmall, style: .continuous)
                            .fill(viewModel.selectedExperienceIndex == index
                                  ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.Radius.cardSmall, style: .continuous)
                            .stroke(viewModel.selectedExperienceIndex == index
                                    ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .interactiveHandCursor()
            }
        }
    }

    private var bulletEditor: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            HStack {
                Text("New responsibility bullet")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    Task { await viewModel.draftBulletWithAI() }
                } label: {
                    HStack(spacing: 4) {
                        if viewModel.isDraftingBullet {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "sparkles")
                        }
                        Text("Draft with AI")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(viewModel.isDraftingBullet)
                .interactiveHandCursor()
            }

            TextEditor(text: $viewModel.bulletText)
                .font(.subheadline)
                .frame(minHeight: 60, maxHeight: 100)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.Radius.input, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            HStack {
                Text("\(viewModel.bulletWordCount)/50 words • \(viewModel.bulletCharacterCount)/400 chars")
                    .font(.caption2)
                    .foregroundColor(viewModel.isBulletOverLimit ? .red : .secondary)
                Spacer()
            }

            if let error = viewModel.draftError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let experience = viewModel.selectedExperience, !experience.responsibilities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Button {
                        withAnimation { showExistingBullets.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: showExistingBullets ? "chevron.down" : "chevron.right")
                                .font(.caption2)
                            Text("Existing bullets (\(experience.responsibilities.count))")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .interactiveHandCursor()

                    if showExistingBullets {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(experience.responsibilities.prefix(6), id: \.self) { bullet in
                                Text("• \(bullet)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Step 3: Category & Scope

    private var step3CategoryAndScope: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            // Category picker
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Skill category")
                    .font(.subheadline.weight(.semibold))

                Picker("Category", selection: $viewModel.selectedCategory) {
                    ForEach(viewModel.skillCategories, id: \.self) { category in
                        Text(category).tag(category)
                    }
                    Divider()
                    Text("New category...").tag("__new__")
                }
                .labelsHidden()
                #if os(macOS)
                .pickerStyle(.menu)
                #endif

                if viewModel.selectedCategory == "__new__" {
                    TextField("Category name (e.g. Cloud, DevOps)", text: $viewModel.newCategoryName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Scope choice (only for job-scoped contexts)
            if viewModel.isJobScoped {
                VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                    Text("Where should this be saved?")
                        .font(.subheadline.weight(.semibold))

                    scopeRadioButton(
                        title: "Only for this application",
                        description: "Scoped to this job's tailored resume",
                        scope: .jobOnly
                    )

                    scopeRadioButton(
                        title: "Add to master resume",
                        description: "Available for all future job applications",
                        scope: .master
                    )
                }
            }

            // Summary preview
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                Text("Summary")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                if let experience = viewModel.selectedExperience {
                    summaryItem(
                        icon: "text.badge.plus",
                        color: .green,
                        text: "Add bullet to \(experience.title) at \(experience.company): \"\(viewModel.trimmedBullet)\""
                    )
                }

                summaryItem(
                    icon: "plus.circle.fill",
                    color: .blue,
                    text: "Add \"\(viewModel.trimmedSkillName)\" to \(viewModel.resolvedCategory.isEmpty ? "skills" : viewModel.resolvedCategory)"
                )
            }

            if let error = viewModel.applyError {
                Label(error, systemImage: "exclamationmark.octagon.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func scopeRadioButton(title: String, description: String, scope: SkillAdditionScope) -> some View {
        Button {
            viewModel.scope = scope
        } label: {
            HStack(alignment: .top, spacing: DesignSystem.Spacing.sm) {
                Image(systemName: viewModel.scope == scope ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(viewModel.scope == scope ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .interactiveHandCursor()
    }

    private func summaryItem(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(3)
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.Radius.badge, style: .continuous)
                .fill(color.opacity(0.06))
        )
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            if viewModel.currentStep > 0 {
                Button("Back") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.currentStep -= 1
                    }
                }
                .buttonStyle(.bordered)
                .interactiveHandCursor()
            }

            Spacer()

            if viewModel.currentStep < 2 {
                Button("Next") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.currentStep += 1
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isCurrentStepValid)
                .interactiveHandCursor()
            } else {
                Button(viewModel.isApplying ? "Adding..." : "Add Skill") {
                    completeFlow()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.isStep3Valid || viewModel.isApplying)
                .interactiveHandCursor()
            }
        }
        .padding(DesignSystem.Spacing.md)
    }

    private var isCurrentStepValid: Bool {
        switch viewModel.currentStep {
        case 0: return viewModel.isStep1Valid
        case 1: return viewModel.isStep2Valid
        case 2: return viewModel.isStep3Valid
        default: return false
        }
    }

    // MARK: - Completion

    private func completeFlow() {
        viewModel.isApplying = true
        viewModel.applyError = nil

        do {
            if viewModel.scope == .master {
                try viewModel.applyToMaster()
                dismiss()
                onComplete([], .master)
            } else {
                let result = try viewModel.buildPatches()
                dismiss()
                onComplete(result.patches, .jobOnly)
            }
        } catch {
            viewModel.applyError = error.localizedDescription
            viewModel.isApplying = false
        }
    }
}

// MARK: - Helpers

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: Swift.max(1, size)).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
