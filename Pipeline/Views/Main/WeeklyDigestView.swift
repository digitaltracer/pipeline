import SwiftUI
import SwiftData
import PipelineKit

struct WeeklyDigestView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \WeeklyDigestSnapshot.weekStart, order: .reverse) private var digests: [WeeklyDigestSnapshot]
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]

    @Bindable var settingsViewModel: SettingsViewModel
    let onOpenApplication: (JobApplication) -> Void
    var highlightedDigestID: UUID? = nil
    var onHandledNotificationOpenRequest: (() -> Void)? = nil

    @State private var highlightedSnapshotID: UUID?
    @State private var generationError: String?

    private let digestService = WeeklyDigestService()

    private var latestDigest: WeeklyDigestSnapshot? {
        digests.first
    }

    private var historyDigests: [WeeklyDigestSnapshot] {
        Array(digests.dropFirst())
    }

    private var currentResumeRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    private var latestCompletedInterval: DateInterval {
        digestService.latestCompletedInterval(
            asOf: Date(),
            schedule: settingsViewModel.weeklyDigestSchedule
        )
    }

    private var isLatestDigestMissing: Bool {
        !digests.contains(where: { abs($0.weekStart.timeIntervalSince(latestCompletedInterval.start)) < 1 })
    }

    private var nextScheduledRun: Date {
        digestService.nextScheduledRun(
            after: Date(),
            schedule: settingsViewModel.weeklyDigestSchedule
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let latestDigest {
                    digestCard(latestDigest, isHero: true)

                    if !historyDigests.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("History")
                                .font(.headline)

                            ForEach(historyDigests) { digest in
                                digestCard(digest, isHero: false)
                            }
                        }
                    }
                } else {
                    emptyStateCard
                }
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .task {
            handleHighlightedDigestIfNeeded()
        }
        .onChange(of: highlightedDigestID) { _, _ in
            handleHighlightedDigestIfNeeded()
        }
        .alert("Weekly Digest Error", isPresented: Binding(
            get: { generationError != nil },
            set: { if !$0 { generationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(generationError ?? "An unknown error occurred.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Weekly Digest")
                        .font(.largeTitle.weight(.bold))
                    Text("A rules-first weekly review of momentum, follow-ups, and where your search is converting.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLatestDigestMissing {
                    Button("Generate Now") {
                        Task {
                            await generateNow()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                }
            }

            HStack(spacing: 12) {
                infoBadge(
                    icon: "clock.badge.checkmark",
                    title: "Next Run",
                    value: nextScheduledRun.formatted(date: .abbreviated, time: .shortened)
                )

                infoBadge(
                    icon: settingsViewModel.weeklyDigestNotificationsEnabled ? "bell.badge.fill" : "bell.slash",
                    title: "Digest Alerts",
                    value: settingsViewModel.weeklyDigestNotificationsEnabled ? "On" : "Off"
                )
            }
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No weekly digest yet")
                .font(.title3.weight(.semibold))

            Text("Pipeline will create your first digest after the next eligible weekly slot or whenever you generate it manually.")
                .foregroundColor(.secondary)

            Text("Next scheduled run: \(nextScheduledRun.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Button("Generate Now") {
                Task {
                    await generateNow()
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
        }
        .padding(20)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func infoBadge(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(DesignSystem.Colors.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func digestCard(_ digest: WeeklyDigestSnapshot, isHero: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(dateRangeText(for: digest))
                        .font(isHero ? .title3.weight(.semibold) : .headline)
                    Text("Generated \(digest.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if isLatestDigestMissing && latestDigest?.id == digest.id {
                    Text("Stale")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.orange)
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: isHero ? 150 : 130), spacing: 12)], spacing: 12) {
                metricCard(title: "Applications", value: "\(digest.newApplicationsCount)", detail: deltaText(digest.newApplicationsDelta))
                metricCard(title: "Response Rate", value: percentText(digest.responseRate), detail: responseDeltaText(digest.responseRateDelta))
                metricCard(title: "Interviews", value: "\(digest.interviewsCompletedCount)", detail: "\(digest.interviewsScheduledCount) next week")
                metricCard(title: "Follow-ups", value: "\(digest.followUpsDueCount)", detail: overdueText(digest.overdueFollowUpsCount))
                metricCard(title: "Avg Match", value: digest.averageMatchScore.map(scoreText) ?? "—", detail: digest.matchScoreDelta.map(matchDeltaText) ?? "No prior baseline")
                metricCard(title: "Needs Tailoring", value: "\(digest.needsTailoringCount)", detail: "Recent applications")
            }

            if let primaryInsight = digest.sortedInsights.first {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Insight", systemImage: "lightbulb.max.fill")
                        .font(.headline)
                        .foregroundColor(.orange)

                    Text(primaryInsight.title)
                        .font(.subheadline.weight(.semibold))

                    Text(primaryInsight.body)
                        .foregroundColor(.secondary)

                    if let evidence = primaryInsight.evidenceText, !evidence.isEmpty {
                        Text(evidence)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            let supportingInsights = Array(digest.sortedInsights.dropFirst())
            if !supportingInsights.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Supporting Signals")
                        .font(.subheadline.weight(.semibold))

                    ForEach(supportingInsights) { insight in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(insight.title)
                                .font(.subheadline.weight(.medium))
                            Text(insight.body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if let evidence = insight.evidenceText, !evidence.isEmpty {
                                Text(evidence)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if !digest.sortedActionItems.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Next Week")
                        .font(.headline)

                    ForEach(digest.sortedActionItems) { item in
                        actionRow(item)
                    }
                }
            }
        }
        .padding(isHero ? 20 : 16)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    highlightedSnapshotID == digest.id ? DesignSystem.Colors.accent : .clear,
                    lineWidth: 2
                )
        )
    }

    private func metricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func actionRow(_ item: WeeklyDigestActionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: item.kind))
                .foregroundColor(item.isOverdue ? .red : DesignSystem.Colors.accent)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))

                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let dueDate = item.dueDate {
                    Text(dueDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(item.isOverdue ? .red : .secondary)
                }
            }

            Spacer()

            if let applicationID = item.applicationID,
               let application = applications.first(where: { $0.id == applicationID }) {
                Button("Open") {
                    onOpenApplication(application)
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignSystem.Colors.accent)
                .font(.caption.weight(.semibold))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func iconName(for kind: WeeklyDigestActionKind) -> String {
        switch kind {
        case .interview:
            return "person.2.fill"
        case .followUp:
            return "calendar.badge.clock"
        case .tailoring:
            return "doc.text.magnifyingglass"
        case .task:
            return "checklist"
        case .summary:
            return "list.bullet.rectangle"
        }
    }

    private func dateRangeText(for digest: WeeklyDigestSnapshot) -> String {
        let endDate = Calendar.current.date(byAdding: .second, value: -1, to: digest.weekEnd) ?? digest.weekEnd
        return "\(digest.weekStart.formatted(date: .abbreviated, time: .omitted)) – \(endDate.formatted(date: .abbreviated, time: .omitted))"
    }

    private func deltaText(_ delta: Int) -> String {
        if delta == 0 { return "No change vs prior week" }
        return delta > 0 ? "+\(delta) vs prior week" : "\(delta) vs prior week"
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func scoreText(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }

    private func responseDeltaText(_ delta: Double) -> String {
        let points = Int((delta * 100).rounded())
        if points == 0 { return "No change vs prior week" }
        return points > 0 ? "+\(points) pts vs prior week" : "\(points) pts vs prior week"
    }

    private func matchDeltaText(_ delta: Double) -> String {
        let points = Int(delta.rounded())
        if points == 0 { return "No change vs prior week" }
        return points > 0 ? "+\(points) pts vs prior week" : "\(points) pts vs prior week"
    }

    private func overdueText(_ count: Int) -> String {
        if count == 0 {
            return "Nothing overdue"
        }
        return "\(count) overdue"
    }

    @MainActor
    private func generateNow(referenceDate: Date = Date()) async {
        do {
            let result = try digestService.generateLatestDigestIfNeeded(
                applications: applications,
                existingDigests: digests,
                in: modelContext,
                currentResumeRevisionID: currentResumeRevision?.id,
                matchPreferences: settingsViewModel.jobMatchPreferences,
                schedule: settingsViewModel.weeklyDigestSchedule,
                referenceDate: referenceDate
            )

            guard case .created = result else {
                return
            }
        } catch {
            generationError = error.localizedDescription
        }
    }

    private func handleHighlightedDigestIfNeeded() {
        guard let highlightedDigestID else { return }
        highlightedSnapshotID = highlightedDigestID
        onHandledNotificationOpenRequest?()
    }
}

#Preview {
    WeeklyDigestView(
        settingsViewModel: SettingsViewModel(),
        onOpenApplication: { _ in }
    )
    .modelContainer(
        for: [
            JobApplication.self,
            JobSearchCycle.self,
            SearchGoal.self,
            InterviewLog.self,
            CompanyProfile.self,
            CompanyResearchSnapshot.self,
            CompanyResearchSource.self,
            CompanySalarySnapshot.self,
            Contact.self,
            ApplicationContactLink.self,
            ApplicationActivity.self,
            InterviewDebrief.self,
            RejectionLog.self,
            InterviewQuestionEntry.self,
            InterviewLearningSnapshot.self,
            RejectionLearningSnapshot.self,
            ApplicationTask.self,
            ApplicationChecklistSuggestion.self,
            ApplicationAttachment.self,
            CoverLetterDraft.self,
            JobMatchAssessment.self,
            ATSCompatibilityAssessment.self,
            ATSCompatibilityScanRun.self,
            ResumeMasterRevision.self,
            ResumeJobSnapshot.self,
            AIUsageRecord.self,
            AIModelRate.self,
            WeeklyDigestSnapshot.self,
            WeeklyDigestInsight.self,
            WeeklyDigestActionItem.self
        ],
        inMemory: true
    )
}
