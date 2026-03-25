import Foundation

public struct SkillAdditionInput: Sendable {
    public let skillName: String
    public let categoryName: String
    public let bulletText: String
    public let experienceIndex: Int

    public init(skillName: String, categoryName: String, bulletText: String, experienceIndex: Int) {
        self.skillName = skillName
        self.categoryName = categoryName
        self.bulletText = bulletText
        self.experienceIndex = experienceIndex
    }
}

public struct SkillAdditionResult: Sendable {
    public let bulletPatch: ResumePatch
    public let skillPatch: ResumePatch

    public var patches: [ResumePatch] { [bulletPatch, skillPatch] }
}

public enum SkillAdditionError: LocalizedError {
    case invalidResumeJSON
    case experienceIndexOutOfBounds(Int)
    case bulletValidationFailed(String)
    case skillValidationFailed(String)
    case duplicateBullet

    public var errorDescription: String? {
        switch self {
        case .invalidResumeJSON:
            return "Resume JSON is invalid."
        case .experienceIndexOutOfBounds(let index):
            return "Experience entry at index \(index) does not exist."
        case .bulletValidationFailed(let reason):
            return "Responsibility bullet rejected: \(reason)"
        case .skillValidationFailed(let reason):
            return "Skill patch rejected: \(reason)"
        case .duplicateBullet:
            return "This responsibility bullet already exists on the selected experience entry."
        }
    }
}

public enum SkillAdditionPatchBuilder {

    /// Builds and validates two ordered patches: a responsibility bullet addition followed by a skill category addition.
    ///
    /// Uses two-phase validation: validates the bullet patch against the original JSON,
    /// applies it to a temporary copy, then validates the skill patch against the modified JSON.
    public static func build(
        input: SkillAdditionInput,
        resumeJSON: String
    ) throws -> SkillAdditionResult {
        guard let data = resumeJSON.data(using: .utf8),
              let schema = try? JSONDecoder().decode(ResumeSchema.self, from: data)
        else {
            throw SkillAdditionError.invalidResumeJSON
        }

        guard schema.experience.indices.contains(input.experienceIndex) else {
            throw SkillAdditionError.experienceIndexOutOfBounds(input.experienceIndex)
        }

        let existingResponsibilities = schema.experience[input.experienceIndex].responsibilities
        let normalizedBullet = input.bulletText.trimmingCharacters(in: .whitespacesAndNewlines)

        let isDuplicate = existingResponsibilities.contains { existing in
            existing.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(normalizedBullet) == .orderedSame
        }
        if isDuplicate {
            throw SkillAdditionError.duplicateBullet
        }

        let newBulletIndex = existingResponsibilities.count

        let bulletPatch = ResumePatch(
            path: "/experience/\(input.experienceIndex)/responsibilities/-",
            operation: .add,
            afterValue: .string(normalizedBullet),
            reason: "Add evidence for skill: \(input.skillName)",
            evidencePaths: [],
            risk: .low
        )

        let skillPatch = ResumePatch(
            path: "/skills/\(input.categoryName)/-",
            operation: .add,
            afterValue: .string(input.skillName),
            reason: "Add skill supported by new responsibility bullet",
            evidencePaths: ["/experience/\(input.experienceIndex)/responsibilities/\(newBulletIndex)"],
            risk: .low
        )

        // Phase 1: Validate the bullet patch against the original JSON.
        let phase1Result = try ResumePatchSafetyValidator.validate(patches: [bulletPatch], originalJSON: resumeJSON)
        if let rejection = phase1Result.rejected.first {
            throw SkillAdditionError.bulletValidationFailed(rejection.reason)
        }

        // Apply the bullet patch to a temporary copy for phase 2 validation.
        let intermediateJSON = try ResumePatchApplier.apply(
            patches: [bulletPatch],
            acceptedPatchIDs: [bulletPatch.id],
            to: resumeJSON
        )

        // Phase 2: Validate the skill patch against the modified JSON.
        let phase2Result = try ResumePatchSafetyValidator.validate(patches: [skillPatch], originalJSON: intermediateJSON)
        if let rejection = phase2Result.rejected.first {
            throw SkillAdditionError.skillValidationFailed(rejection.reason)
        }

        return SkillAdditionResult(bulletPatch: bulletPatch, skillPatch: skillPatch)
    }

    /// Checks whether a skill already exists in any category of the resume.
    /// Returns the category name if found, nil otherwise.
    public static func existingCategory(
        for skillName: String,
        in resumeJSON: String
    ) -> String? {
        guard let data = resumeJSON.data(using: .utf8),
              let schema = try? JSONDecoder().decode(ResumeSchema.self, from: data)
        else {
            return nil
        }

        let normalizedSkill = skillName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        for (category, skills) in schema.skills {
            if skills.contains(where: { $0.lowercased() == normalizedSkill }) {
                return category
            }
        }

        return nil
    }
}
