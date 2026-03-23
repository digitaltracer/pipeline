import SwiftUI
import SwiftData
import PipelineKit

struct ATSCompatibilitySection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]

    let application: JobApplication
    let settingsViewModel: SettingsViewModel
    let onGenerateFixes: (ATSCompatibilityAssessment) -> Void
    let onGenerateQuickFixes: (ATSCompatibilityAssessment) -> Void

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

    private var latestScanRuns: [ATSCompatibilityScanRun] {
        Array(application.sortedATSScanRuns.prefix(4))
    }

    private var visibleMatchedKeywords: [String] {
        guard let assessment else { return [] }
        let promoted = Set(assessment.skillsPromotionKeywords)
        return assessment.matchedKeywords.filter { !promoted.contains($0) }
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
            await refreshIfNeeded(force: false, trigger: .autoViewRefresh)
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
                Task { await refreshIfNeeded(force: true, trigger: .manualRescan) }
            }
            .buttonStyle(.bordered)
            .disabled(isRefreshing)
            .interactiveHandCursor()
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
                provenanceBlock(assessment)

                if let summary = normalized(assessment.summary) {
                    Text(summary)
                        .font(.subheadline)
                }

                complianceRows(assessment)

                findingGroup(
                    title: "Successes",
                    severity: .success,
                    values: successFindings(for: assessment)
                )

                findingGroup(
                    title: "Keyword Evidence",
                    severity: .warning,
                    values: assessment.keywordEvidenceSummary
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

                keywordList(title: "Missing From Resume", values: assessment.missingKeywords, tint: .orange)
                keywordList(title: "Present But Not In Skills", values: assessment.skillsPromotionKeywords, tint: .blue)
                keywordList(title: "Matched Keywords", values: visibleMatchedKeywords, tint: .green)

                actionRow(assessment)
                historySection
            case .blocked:
                Label(
                    assessment.lastErrorMessage
                        ?? assessment.blockedReason?.message
                        ?? "ATS analysis is missing the inputs required to run.",
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

    private func provenanceBlock(_ assessment: ATSCompatibilityAssessment) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let sourceKind = assessment.resumeSourceKind {
                Label("Using \(sourceKind.title)", systemImage: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ATSFlowLayout(values: provenanceTags(for: assessment)) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.10))
                    )
            }
        }
    }

    private func complianceRows(_ assessment: ATSCompatibilityAssessment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            complianceRow(
                title: "Contact",
                state: contactState(for: assessment),
                detail: contactDetail(for: assessment)
            )
            complianceRow(
                title: "Sections",
                state: sectionState(for: assessment),
                detail: sectionDetail(for: assessment)
            )
            complianceRow(
                title: "Format",
                state: formatState(for: assessment),
                detail: formatDetail(for: assessment)
            )
        }
    }

    private func complianceRow(title: String, state: ATSFindingSeverity, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon(for: state))
                .foregroundColor(color(for: state))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color(for: state).opacity(0.08))
        )
    }

    private func actionRow(_ assessment: ATSCompatibilityAssessment) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if !assessment.skillsPromotionKeywords.isEmpty {
                    Button("Add Evidence-Backed Keywords to Skills") {
                        onGenerateQuickFixes(assessment)
                    }
                    .buttonStyle(.bordered)
                    .interactiveHandCursor()
                }

                Button("Generate ATS Fixes") {
                    onGenerateFixes(assessment)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .interactiveHandCursor()
            }

            if isStale {
                Label(
                    "This ATS scan is stale because the job description, preferred resume source, or scoring version changed.",
                    systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90"
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        if !latestScanRuns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Scans")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ForEach(Array(latestScanRuns.enumerated()), id: \.element.id) { index, run in
                    historyRow(run, previous: latestScanRuns[safe: index + 1])
                }
            }
        }
    }

    private func historyRow(_ run: ATSCompatibilityScanRun, previous: ATSCompatibilityScanRun?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(run.scanTrigger.title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(scoreDeltaText(for: run, previous: previous))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(historyTimestamp(for: run))
                .font(.caption)
                .foregroundColor(.secondary)

            if let changeSummary = changeSummary(for: run, previous: previous) {
                Text(changeSummary)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.06))
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
            findings.append("ATS scan ran against a Pipeline-managed structured resume source.")
        }
        if !visibleMatchedKeywords.isEmpty {
            findings.append("\(visibleMatchedKeywords.count) weighted JD keyword\(visibleMatchedKeywords.count == 1 ? "" : "s") already appear in the resume.")
        }
        if assessment.formatScore == 100 {
            findings.append("Pipeline's JSON-first export checks passed for the current resume.")
        }
        if assessment.hasExperienceSection && assessment.hasEducationSection && assessment.hasSkillsSection {
            findings.append("Experience, Education, and Skills sections were detected.")
        }
        return findings
    }

    private func provenanceTags(for assessment: ATSCompatibilityAssessment) -> [String] {
        var tags: [String] = []
        tags.append("Scorer \(assessment.scoringVersion)")
        if let latestRun = latestScanRuns.first {
            tags.append(latestRun.scanTrigger.title)
        }
        if assessment.resumeSourceSnapshotID != nil {
            tags.append("Tailored Snapshot")
        } else if assessment.resumeSourceRevisionID != nil {
            tags.append("Master Resume")
        }
        return tags
    }

    private func contactState(for assessment: ATSCompatibilityAssessment) -> ATSFindingSeverity {
        if !assessment.contactCriticalFindings.isEmpty {
            return .critical
        }
        if !assessment.contactWarningFindings.isEmpty {
            return .warning
        }
        return .success
    }

    private func contactDetail(for assessment: ATSCompatibilityAssessment) -> String {
        if let critical = assessment.contactCriticalFindings.first {
            return critical
        }
        if let warning = assessment.contactWarningFindings.first {
            return warning
        }
        return "Email and phone parsed correctly."
    }

    private func sectionState(for assessment: ATSCompatibilityAssessment) -> ATSFindingSeverity {
        if assessment.hasExperienceSection && assessment.hasEducationSection && assessment.hasSkillsSection {
            return .success
        }
        return .warning
    }

    private func sectionDetail(for assessment: ATSCompatibilityAssessment) -> String {
        if assessment.sectionFindings.isEmpty {
            return "Experience, Education, and Skills were detected."
        }
        return assessment.sectionFindings.joined(separator: " ")
    }

    private func formatState(for assessment: ATSCompatibilityAssessment) -> ATSFindingSeverity {
        if !assessment.formatCriticalFindings.isEmpty {
            return .critical
        }
        if !assessment.formatWarningFindings.isEmpty {
            return .warning
        }
        return .success
    }

    private func formatDetail(for assessment: ATSCompatibilityAssessment) -> String {
        if let critical = assessment.formatCriticalFindings.first {
            return critical
        }
        if let warning = assessment.formatWarningFindings.first {
            return warning
        }
        return "JSON-first ATS checks passed for Pipeline export assumptions."
    }

    private func scoreDeltaText(for run: ATSCompatibilityScanRun, previous: ATSCompatibilityScanRun?) -> String {
        guard let score = run.overallScore else {
            return run.status == .failed ? "Failed" : run.status.title
        }
        guard let previousScore = previous?.overallScore else {
            return "\(score)%"
        }
        let delta = score - previousScore
        if delta == 0 {
            return "\(score)%"
        }
        let sign = delta > 0 ? "+" : ""
        return "\(score)% (\(sign)\(delta))"
    }

    private func historyTimestamp(for run: ATSCompatibilityScanRun) -> String {
        let date = run.scoredAt ?? run.createdAt
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func changeSummary(for run: ATSCompatibilityScanRun, previous: ATSCompatibilityScanRun?) -> String? {
        guard let previous else { return "Initial persisted ATS scan." }
        var reasons: [String] = []

        if run.jobDescriptionHash != previous.jobDescriptionHash {
            reasons.append("JD changed")
        }
        if run.resumeSourceFingerprint != previous.resumeSourceFingerprint {
            reasons.append("Resume changed")
        }
        if run.scoringVersion != previous.scoringVersion {
            reasons.append("Scorer updated")
        }
        if run.warningFindings != previous.warningFindings || run.criticalFindings != previous.criticalFindings {
            reasons.append("Findings changed")
        }

        if reasons.isEmpty {
            return "Inputs matched the prior scan."
        }
        return reasons.joined(separator: " • ")
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
    private func refreshIfNeeded(force: Bool, trigger: ATSScanTrigger) async {
        isRefreshing = true
        defer { isRefreshing = false }
        await ATSCompatibilityCoordinator.shared.refresh(
            application: application,
            modelContext: modelContext,
            settingsViewModel: settingsViewModel,
            force: force,
            trigger: trigger
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

    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension ATSAssessmentStatus {
    var title: String {
        switch self {
        case .ready:
            return "Ready"
        case .blocked:
            return "Blocked"
        case .failed:
            return "Failed"
        }
    }
}
