import Foundation
import PipelineKit

struct ATSFixContext: Equatable {
    let summary: String
    let missingKeywords: [String]
    let criticalFindings: [String]
    let warningFindings: [String]

    init(assessment: ATSCompatibilityAssessment) {
        self.summary = assessment.summary ?? ""
        self.missingKeywords = assessment.missingKeywords
        self.criticalFindings = assessment.criticalFindings
        self.warningFindings = assessment.warningFindings
    }

    var additionalPromptContext: String {
        var lines: [String] = []

        if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("ATS Summary: \(summary)")
        }

        if !missingKeywords.isEmpty {
            lines.append("Prioritize these missing keywords when evidence exists: \(missingKeywords.joined(separator: ", ")).")
        }

        if !criticalFindings.isEmpty {
            lines.append("Address these critical ATS findings: \(criticalFindings.joined(separator: " | ")).")
        }

        if !warningFindings.isEmpty {
            lines.append("Address these warning ATS findings: \(warningFindings.joined(separator: " | ")).")
        }

        lines.append("Generate multi-section ATS fixes only when they are grounded in existing resume evidence.")
        return lines.joined(separator: "\n")
    }
}

struct ATSQuickFixContext: Equatable {
    let summary: String
    let promotedKeywords: [String]
    let unsupportedKeywords: [String]

    init(assessment: ATSCompatibilityAssessment, unsupportedKeywords: [String] = []) {
        self.summary = assessment.summary ?? ""
        self.promotedKeywords = assessment.skillsPromotionKeywords
        self.unsupportedKeywords = unsupportedKeywords
    }
}

enum ResumeTailoringMode: Equatable {
    case standard
    case atsFixes(ATSFixContext)
    case atsQuickFixes(ATSQuickFixContext)
    case skillAddition

    var navigationTitle: String {
        switch self {
        case .standard:
            return "Tailor Resume"
        case .atsFixes:
            return "ATS Fixes"
        case .atsQuickFixes:
            return "ATS Quick Fixes"
        case .skillAddition:
            return "Add Skill Evidence"
        }
    }

    var targetLabel: String {
        switch self {
        case .standard:
            return "Target"
        case .atsFixes, .atsQuickFixes:
            return "ATS Focus"
        case .skillAddition:
            return "Skill"
        }
    }

    var generationTitle: String {
        switch self {
        case .standard:
            return "Generating Tailored Suggestions"
        case .atsFixes:
            return "Generating ATS Fixes"
        case .atsQuickFixes:
            return "Preparing ATS Quick Fixes"
        case .skillAddition:
            return "Preparing Skill Addition"
        }
    }

    var generationSubtitle: String {
        switch self {
        case .standard:
            return "Live timeline of resume tailoring steps."
        case .atsFixes:
            return "Live timeline of ATS-focused resume patch generation."
        case .atsQuickFixes:
            return "Review deterministic ATS-safe skills patches before saving."
        case .skillAddition:
            return "Review skill evidence patches before saving."
        }
    }

    var usageFeature: AIUsageFeature? {
        switch self {
        case .standard:
            return .resumeTailoring
        case .atsFixes:
            return .resumeATSFixes
        case .atsQuickFixes, .skillAddition:
            return nil
        }
    }
}
