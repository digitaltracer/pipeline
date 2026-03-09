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

enum ResumeTailoringMode: Equatable {
    case standard
    case atsFixes(ATSFixContext)

    var navigationTitle: String {
        switch self {
        case .standard:
            return "Tailor Resume"
        case .atsFixes:
            return "ATS Fixes"
        }
    }

    var targetLabel: String {
        switch self {
        case .standard:
            return "Target"
        case .atsFixes:
            return "ATS Focus"
        }
    }

    var generationTitle: String {
        switch self {
        case .standard:
            return "Generating Tailored Suggestions"
        case .atsFixes:
            return "Generating ATS Fixes"
        }
    }

    var generationSubtitle: String {
        switch self {
        case .standard:
            return "Live timeline of resume tailoring steps."
        case .atsFixes:
            return "Live timeline of ATS-focused resume patch generation."
        }
    }

    var usageFeature: AIUsageFeature {
        switch self {
        case .standard:
            return .resumeTailoring
        case .atsFixes:
            return .resumeATSFixes
        }
    }
}
