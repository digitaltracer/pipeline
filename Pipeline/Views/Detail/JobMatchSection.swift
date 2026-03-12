import SwiftUI
import SwiftData
import PipelineKit

struct JobMatchSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]

    let application: JobApplication
    let settingsViewModel: SettingsViewModel
    let onRefresh: () -> Void

    @State private var isExpanded = true

    private var currentResumeRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    private var matchPreferences: JobMatchPreferences {
        settingsViewModel.jobMatchPreferences
    }

    private var assessment: JobMatchAssessment? {
        application.matchAssessment
    }

    private var isStale: Bool {
        guard let assessment else { return false }
        return JobMatchScoringService.isStale(
            assessment,
            application: application,
            currentResumeRevisionID: currentResumeRevision?.id,
            preferences: matchPreferences
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 14) {
                    scoreRow
                    componentGrid
                    statusContent
                }
                .padding(.top, 12)
            } label: {
                HStack {
                    Label("Job Match", systemImage: "bolt.badge.checkmark")
                        .font(.headline)

                    Spacer()

                    JobMatchBadge(
                        application: application,
                        currentResumeRevisionID: currentResumeRevision?.id,
                        matchPreferences: matchPreferences
                    )
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    @ViewBuilder
    private var scoreRow: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assessment?.formattedOverallScore ?? "—")
                    .font(.system(size: 30, weight: .bold, design: .rounded))

                if let scoredAt = assessment?.scoredAt {
                    Text(timestampText(for: scoredAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(isStale ? "Refresh Score" : "Re-score") {
                onRefresh()
            }
            .buttonStyle(.bordered)
        }
    }

    private var componentGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            scoreCard(title: "Skills", score: assessment?.skillsScore)
            scoreCard(title: "Experience", score: assessment?.experienceScore)
            scoreCard(title: "Salary", score: assessment?.salaryScore)
            scoreCard(title: "Location", score: assessment?.locationScore)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let assessment {
            switch assessment.status {
            case .ready:
                if let summary = normalized(assessment.summary) {
                    Text(summary)
                        .font(.subheadline)
                }

                if let gapAnalysis = normalized(assessment.gapAnalysis) {
                    Text(gapAnalysis)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !assessment.matchedSkills.isEmpty {
                    skillList(title: "Matched Skills", values: assessment.matchedSkills, tint: .green)
                }

                if !assessment.missingSkills.isEmpty {
                    skillList(title: "Gaps", values: assessment.missingSkills, tint: .orange)
                }

                if isStale {
                    Label("This score is stale because the resume, preferences, or job description changed.", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .blocked:
                Label(
                    assessment.blockedReason?.message ?? "This application is missing the inputs required to score the match.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            case .failed:
                Label(
                    assessment.lastErrorMessage ?? "Job match scoring failed.",
                    systemImage: "exclamationmark.octagon.fill"
                )
                .font(.subheadline)
                .foregroundColor(.red)
            }
        } else {
            Label("No match score has been generated yet.", systemImage: "sparkles")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func scoreCard(title: String, score: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(score.map { "\($0)%" } ?? "N/A")
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func skillList(title: String, values: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            FlowLayout(values: values) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundColor(tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.12))
                    )
            }
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func timestampText(for date: Date) -> String {
        if isStale {
            return "Stale • scored \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Scored \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

private struct FlowLayout<Content: View>: View {
    let values: [String]
    let content: (String) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values.chunked(into: 3), id: \.self) { row in
                HStack {
                    ForEach(row, id: \.self, content: content)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: Swift.max(1, size)).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
