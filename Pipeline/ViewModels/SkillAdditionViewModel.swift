import Foundation
import Observation
import SwiftData
import PipelineKit

enum SkillAdditionScope: Equatable {
    case master
    case jobOnly
}

@MainActor
@Observable
final class SkillAdditionViewModel {

    // MARK: - Step 1: Skill Name

    var skillName: String = ""

    // MARK: - Step 2: Experience Linking

    var selectedExperienceIndex: Int?
    var bulletText: String = ""
    var isDraftingBullet = false
    var draftError: String?

    // MARK: - Step 3: Category & Scope

    var selectedCategory: String = ""
    var newCategoryName: String = ""
    var scope: SkillAdditionScope = .jobOnly

    // MARK: - State

    var currentStep: Int = 0
    var isApplying = false
    var applyError: String?

    // MARK: - Context

    let resumeJSON: String
    let schema: ResumeSchema
    let application: JobApplication?
    let missingSkills: [String]
    private let settingsViewModel: SettingsViewModel
    private var modelContext: ModelContext?

    /// Whether the wizard was opened from a job-specific context (entry points 1 & 2) vs master workspace (entry point 3).
    var isJobScoped: Bool { application != nil }

    init(
        resumeJSON: String,
        application: JobApplication? = nil,
        settingsViewModel: SettingsViewModel,
        modelContext: ModelContext? = nil,
        prefilledSkill: String = "",
        missingSkills: [String] = []
    ) {
        self.resumeJSON = resumeJSON
        self.application = application
        self.settingsViewModel = settingsViewModel
        self.modelContext = modelContext
        self.missingSkills = missingSkills
        self.skillName = prefilledSkill

        if let data = resumeJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(ResumeSchema.self, from: data) {
            self.schema = decoded
        } else {
            self.schema = ResumeSchema(
                name: "",
                contact: .init(phone: "", email: "", linkedin: "", github: ""),
                education: [],
                experience: [],
                projects: [],
                skills: [:]
            )
        }

        // Default scope based on context
        if application == nil {
            scope = .master
        }

        // Skip step 1 if a skill was prefilled (e.g. clicked from job match gaps)
        if !prefilledSkill.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            currentStep = 1
        }

        // Pre-select first category if available
        if let firstCategory = schema.skills.keys.sorted().first {
            selectedCategory = firstCategory
        }
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - Computed Properties

    var trimmedSkillName: String {
        skillName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isStep1Valid: Bool {
        !trimmedSkillName.isEmpty
    }

    var selectedExperience: ResumeSchema.ExperienceEntry? {
        guard let index = selectedExperienceIndex,
              schema.experience.indices.contains(index) else { return nil }
        return schema.experience[index]
    }

    var trimmedBullet: String {
        bulletText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var bulletWordCount: Int {
        trimmedBullet.split(whereSeparator: \.isWhitespace).count
    }

    var bulletCharacterCount: Int {
        trimmedBullet.count
    }

    var isBulletOverLimit: Bool {
        bulletWordCount > 50 || bulletCharacterCount > 400
    }

    var isStep2Valid: Bool {
        selectedExperienceIndex != nil && !trimmedBullet.isEmpty && !isBulletOverLimit
    }

    var resolvedCategory: String {
        let cat = selectedCategory == "__new__"
            ? newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedCategory
        return cat
    }

    var isStep3Valid: Bool {
        !resolvedCategory.isEmpty
    }

    var skillCategories: [String] {
        schema.skills.keys.sorted()
    }

    var existingCategoryForSkill: String? {
        SkillAdditionPatchBuilder.existingCategory(for: trimmedSkillName, in: resumeJSON)
    }

    var hasExperienceEntries: Bool {
        !schema.experience.isEmpty
    }

    // MARK: - AI Bullet Drafting

    func draftBulletWithAI() async {
        guard let experience = selectedExperience else { return }

        let provider = settingsViewModel.selectedAIProvider
        let model = settingsViewModel.preferredModel(for: provider)

        guard !model.isEmpty else {
            draftError = "No AI model configured. Please check Settings."
            return
        }

        isDraftingBullet = true
        draftError = nil

        let startedAt = Date()

        do {
            let draft = try await settingsViewModel.withAPIKeyWaterfall(for: provider) { apiKey in
                try await SkillBulletDraftingService.draft(
                    provider: provider,
                    apiKey: apiKey,
                    model: model,
                    skillName: trimmedSkillName,
                    jobTitle: experience.title,
                    company: experience.company,
                    existingResponsibilities: experience.responsibilities,
                    jobDescription: application?.jobDescription
                )
            }
            bulletText = draft.bulletText

            if let modelContext {
                _ = try? AIUsageLedgerService.record(
                    feature: .skillBulletDrafting,
                    provider: provider,
                    model: model,
                    usage: draft.usage,
                    status: .succeeded,
                    applicationID: application?.id,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    in: modelContext
                )
            }
        } catch {
            draftError = error.localizedDescription

            if let modelContext {
                _ = try? AIUsageLedgerService.record(
                    feature: .skillBulletDrafting,
                    provider: provider,
                    model: model,
                    usage: nil,
                    status: .failed,
                    applicationID: application?.id,
                    startedAt: startedAt,
                    finishedAt: Date(),
                    errorMessage: error.localizedDescription,
                    in: modelContext
                )
            }
        }

        isDraftingBullet = false
    }

    // MARK: - Patch Building

    func buildPatches() throws -> SkillAdditionResult {
        try SkillAdditionPatchBuilder.build(
            input: SkillAdditionInput(
                skillName: trimmedSkillName,
                categoryName: resolvedCategory,
                bulletText: trimmedBullet,
                experienceIndex: selectedExperienceIndex ?? 0
            ),
            resumeJSON: resumeJSON
        )
    }

    // MARK: - Apply to Master

    func applyToMaster() throws {
        guard let modelContext else {
            throw SkillAdditionError.invalidResumeJSON
        }

        let result = try buildPatches()

        // Apply both patches in order
        let patchedJSON = try ResumePatchApplier.apply(
            patches: result.patches,
            acceptedPatchIDs: Set(result.patches.map(\.id)),
            to: resumeJSON
        )

        // Validate the final JSON
        let validation = try ResumeSchemaValidator.validate(jsonText: patchedJSON)

        try ResumeStoreService.saveMasterRevision(
            rawJSON: validation.normalizedJSON,
            unknownFieldPaths: validation.unknownFieldPaths,
            in: modelContext
        )
    }
}
