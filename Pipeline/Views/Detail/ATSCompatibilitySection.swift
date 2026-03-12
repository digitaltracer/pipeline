import SwiftUI
import SwiftData
import PipelineKit

struct ATSCompatibilitySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]

    let application: JobApplication
    let onGenerateFixes: (ATSCompatibilityAssessment) -> Void

    @State private var isExpanded = true
    @State private var isRefreshing = false

    private var currentMasterRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    private var assessment: ATSCompatibilityAssessment? {
        application.atsAssessment
    }

    private var preferredResumeSource: ResumeSourceSelection? {
        try? ResumeStoreService.preferredResumeSource(for: application, in: modelContext)
    }

    private var isStale: Bool {
        guard let assessment else { return false }
        return ATSCompatibilityScoringService.isStale(
            assessment,
            application: application,
            resumeSource: preferredResumeSource
        )
    }

    private var refreshTaskKey: String {
        [
            application.id.uuidString,
            application.jobDescription ?? "",
            application.sortedResumeSnapshots.first?.id.uuidString ?? "no-snapshot",
            currentMasterRevision?.id.uuidString ?? "no-master",
            assessment?.updatedAt.timeIntervalSinceReferenceDate.description ?? "no-assessment"
        ].joined(separator: "|")
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
                    Label("ATS Compatibility", systemImage: "text.badge.checkmark")
                        .font(.headline)

                    Spacer()

                    assessmentBadge
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
        .task(id: refreshTaskKey) {
            await refreshIfNeeded(force: false)
        }
    }

    @ViewBuilder
    private var assessmentBadge: some View {
        if let assessment,
           let score = assessment.overallScore {
            Text("\(score)%")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Capsule().fill(DesignSystem.Colors.accent.opacity(0.18)))
        } else if isRefreshing {
            ProgressView()
                .controlSize(.small)
        } else {
            Text("Pending")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
        }
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
                } else if let source = preferredResumeSource {
                    Text("Using \(source.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Button(isRefreshing ? "Refreshing..." : (isStale ? "Refresh ATS" : "Re-scan")) {
                Task { await refreshIfNeeded(force: true) }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
        }
    }

    private var componentGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 10)], spacing: 10) {
            scoreCard(title: "Keywords", score: assessment?.keywordScore)
            scoreCard(title: "Sections", score: assessment?.sectionScore)
            scoreCard(title: "Contact", score: assessment?.contactScore)
            scoreCard(title: "Format", score: assessment?.formatScore)
        }
    }

    @ViewBuilder
    private var statusContent: some View {
        if let assessment {
            switch assessment.status {
            case .ready:
                if let sourceKind = assessment.resumeSourceKind {
                    Label("Using \(sourceKind.title)", systemImage: "doc.text")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let summary = normalized(assessment.summary) {
                    Text(summary)
                        .font(.subheadline)
                }

                findingGroup(
                    title: "Successes",
                    severity: .success,
                    values: successFindings(for: assessment)
                )

                findingGroup(
                    title: "Warnings",
                    severity: .warning,
                    values: assessment.warningFindings
                )

                findingGroup(
                    title: "Critical",
                    severity: .critical,
                    values: assessment.criticalFindings
                )

                keywordList(title: "Missing Keywords", values: assessment.missingKeywords, tint: .orange)
                keywordList(title: "Matched Keywords", values: assessment.matchedKeywords, tint: .green)

                HStack(spacing: 12) {
                    Button("Generate ATS Fixes") {
                        onGenerateFixes(assessment)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)

                    if isStale {
                        Label(
                            "This ATS scan is stale because the job description or preferred resume changed.",
                            systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            case .blocked:
                Label(
                    assessment.blockedReason?.message ?? "ATS analysis is missing the inputs required to run.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            case .failed:
                Label(
                    assessment.lastErrorMessage ?? "ATS analysis failed.",
                    systemImage: "exclamationmark.octagon.fill"
                )
                .font(.subheadline)
                .foregroundColor(.red)
            }
        } else {
            Label("No ATS scan has been generated yet.", systemImage: "text.badge.checkmark")
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

    @ViewBuilder
    private func findingGroup(
        title: String,
        severity: ATSFindingSeverity,
        values: [String]
    ) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ForEach(values, id: \.self) { value in
                    Label(value, systemImage: icon(for: severity))
                        .font(.caption)
                        .foregroundColor(color(for: severity))
                }
            }
        }
    }

    @ViewBuilder
    private func keywordList(title: String, values: [String], tint: Color) -> some View {
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ATSFlowLayout(values: values) { value in
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
    }

    private func successFindings(for assessment: ATSCompatibilityAssessment) -> [String] {
        var findings: [String] = []
        if assessment.contactScore == 100 {
            findings.append("Contact info parsed correctly.")
        }
        if assessment.sectionScore ?? 0 > 0, !application.sortedResumeSnapshots.isEmpty || currentMasterRevision != nil {
            let resumeSource = assessment.resumeSourceKind
            if resumeSource != nil {
                findings.append("ATS scan ran against a Pipeline-managed resume source.")
            }
        }
        if !assessment.matchedKeywords.isEmpty {
            findings.append("\(assessment.matchedKeywords.count) weighted JD keyword\(assessment.matchedKeywords.count == 1 ? "" : "s") already appear in the resume.")
        }
        if assessment.formatScore == 100 {
            findings.append("Pipeline export format remains machine-readable for ATS parsing.")
        }
        if (assessment.sectionScore ?? 0) == 100 {
            findings.append("Experience, Education, and Skills sections were detected.")
        }
        return findings
    }

    private func icon(for severity: ATSFindingSeverity) -> String {
        switch severity {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.circle.fill"
        case .critical:
            return "xmark.octagon.fill"
        }
    }

    private func color(for severity: ATSFindingSeverity) -> Color {
        switch severity {
        case .success:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func timestampText(for date: Date) -> String {
        if isStale {
            return "Stale • scanned \(date.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Scanned \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    @MainActor
    private func refreshIfNeeded(force: Bool) async {
        if !force,
           let assessment,
           !ATSCompatibilityScoringService.shouldAutoRefresh(
            assessment,
            application: application,
            resumeSource: preferredResumeSource
           ) {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }
        await ATSCompatibilityCoordinator.shared.refresh(
            application: application,
            modelContext: modelContext,
            force: force
        )
    }
}

private struct ATSFlowLayout<Content: View>: View {
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
