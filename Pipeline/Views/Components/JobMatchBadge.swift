import SwiftUI
import PipelineKit

struct JobMatchBadge: View {
    let application: JobApplication
    let currentResumeRevisionID: UUID?
    let matchPreferences: JobMatchPreferences

    private var assessment: JobMatchAssessment? {
        application.matchAssessment
    }

    private var isStale: Bool {
        guard let assessment else { return false }
        return JobMatchScoringService.isStale(
            assessment,
            application: application,
            currentResumeRevisionID: currentResumeRevisionID,
            preferences: matchPreferences
        )
    }

    private var labelText: String {
        guard let assessment else { return "Unscored" }

        switch assessment.status {
        case .ready:
            if let score = assessment.overallScore {
                return isStale ? "Stale \(score)%" : "\(score)% Match"
            }
            return "Match"
        case .blocked:
            return "Needs Input"
        case .failed:
            return "Match Failed"
        }
    }

    private var tint: Color {
        guard let assessment else { return .secondary }
        switch assessment.status {
        case .ready:
            if isStale {
                return .secondary
            }
            let score = assessment.overallScore ?? 0
            if score >= 80 {
                return .green
            }
            if score >= 60 {
                return .orange
            }
            return .red
        case .blocked:
            return .secondary
        case .failed:
            return .red
        }
    }

    var body: some View {
        Text(labelText)
            .font(.caption2.weight(.semibold))
            .foregroundColor(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(tint.opacity(isStale ? 0.10 : 0.14))
            )
    }
}
