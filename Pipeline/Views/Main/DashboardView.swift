import SwiftUI
import SwiftData
import Charts
import PipelineKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \JobSearchCycle.updatedAt, order: .reverse) private var cycles: [JobSearchCycle]
    @Query(sort: \SearchGoal.updatedAt, order: .reverse) private var goals: [SearchGoal]
    @Query(sort: \ResumeMasterRevision.createdAt, order: .reverse) private var resumeRevisions: [ResumeMasterRevision]
    @Query(sort: \RejectionLearningSnapshot.generatedAt, order: .reverse) private var rejectionLearningSnapshots: [RejectionLearningSnapshot]
    @State private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme

    @State private var showingSearchCycleSheet = false

    let settingsViewModel: SettingsViewModel
    var onboardingProgress: OnboardingProgress? = nil
    var onOnboardingAction: ((OnboardingAction) -> Void)? = nil
    var onHideOnboardingGuidance: (() -> Void)? = nil

    init(
        settingsViewModel: SettingsViewModel = SettingsViewModel(),
        onboardingProgress: OnboardingProgress? = nil,
        onOnboardingAction: ((OnboardingAction) -> Void)? = nil,
        onHideOnboardingGuidance: (() -> Void)? = nil
    ) {
        self.settingsViewModel = settingsViewModel
        self.onboardingProgress = onboardingProgress
        self.onOnboardingAction = onOnboardingAction
        self.onHideOnboardingGuidance = onHideOnboardingGuidance
    }

    private var refreshToken: String {
        let appToken = applications.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        let cycleToken = cycles.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        let goalToken = goals.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }.joined(separator: "|")
        return "\(viewModel.selectedScope.rawValue)|\(settingsViewModel.analyticsBaseCurrency.rawValue)|\(currentResumeRevision?.id.uuidString ?? "none")|\(settingsViewModel.jobMatchPreferences.fingerprint)|\(appToken)|\(cycleToken)|\(goalToken)"
    }

    private var currentResumeRevision: ResumeMasterRevision? {
        resumeRevisions.first(where: \.isCurrent) ?? resumeRevisions.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if let analytics = viewModel.analytics {
                    if viewModel.summaryCards.isEmpty {
                        emptyStateCard
                    } else {
                        if let cycle = analytics.activeCycle {
                            cycleStatsBar(cycle: cycle)
                        }
                        overviewSection(analytics: analytics)
                        dashboardContent(analytics: analytics)
                    }
                } else if viewModel.isRefreshing {
                    loadingCard
                } else {
                    emptyStateCard
                }
            }
            .frame(maxWidth: 1480, alignment: .leading)
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .task(id: refreshToken) {
            let token = refreshToken
            await viewModel.refresh(
                token: token,
                applications: applications,
                cycles: cycles,
                goals: goals,
                baseCurrency: settingsViewModel.analyticsBaseCurrency,
                rejectionLearningSnapshot: rejectionLearningSnapshots.first,
                currentResumeRevisionID: currentResumeRevision?.id,
                matchPreferences: settingsViewModel.jobMatchPreferences
            )
        }
        .onDisappear {
            viewModel.cancelRefresh()
        }
        .sheet(isPresented: $showingSearchCycleSheet) {
            SearchCycleSheet()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    headerTitleBlock
                    Spacer(minLength: 12)
                    dashboardHeaderControls
                }

                VStack(alignment: .leading, spacing: 18) {
                    headerTitleBlock
                    dashboardHeaderControls
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    dashboardContextBadges
                }

                VStack(alignment: .leading, spacing: 10) {
                    dashboardContextBadges
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.surfaceElevated(colorScheme),
                            DesignSystem.Colors.surface(colorScheme),
                            DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.10)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.22),
                            DesignSystem.Colors.accent.opacity(0.20),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    private var headerTitleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Executive Overview")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("Dashboard")
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text(headerSummaryText)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(maxWidth: 640, alignment: .leading)
        }
    }

    private var headerSummaryText: String {
        guard let analytics = viewModel.analytics else {
            return "Track search momentum, conversion quality, and cycle execution from one place."
        }

        if let activeCycle = analytics.activeCycle {
            return "Monitoring \(analytics.comparisonLabel) for \(activeCycle.name), with hiring momentum, goals, and compensation signals in one view."
        }

        return "Monitoring \(analytics.comparisonLabel) with conversion, checklist, and compensation signals in one view."
    }

    @ViewBuilder
    private var dashboardContextBadges: some View {
        dashboardBadge(
            icon: "calendar.badge.clock",
            title: "Window",
            value: viewModel.analytics?.comparisonLabel.capitalized ?? viewModel.selectedScope.title
        )

        dashboardBadge(
            icon: "arrow.left.arrow.right.circle.fill",
            title: "Base Currency",
            value: settingsViewModel.analyticsBaseCurrency.rawValue
        )

        dashboardBadge(
            icon: "viewfinder.circle",
            title: "Active Cycle",
            value: viewModel.analytics?.activeCycle?.name ?? "No active cycle"
        )

        if let analytics = viewModel.analytics, analytics.fxUsedFallback || analytics.missingSalaryConversionCount > 0 {
            dashboardBadge(
                icon: "arrow.clockwise",
                title: "FX Status",
                value: analytics.fxUsedFallback ? "Using cached rates" : "\(analytics.missingSalaryConversionCount) missing conversions"
            )
        }
    }

    private func dashboardBadge(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.55 : 0.9))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private var dashboardHeaderControls: some View {
        VStack(alignment: .trailing, spacing: 10) {
            Label("Analytics Window", systemImage: "slider.horizontal.3")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    dashboardScopeSwitcher
                    dashboardToolbarActions
                }

                VStack(alignment: .trailing, spacing: 10) {
                    dashboardScopeSwitcher
                    dashboardToolbarActions
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.68 : 0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private var dashboardScopeSwitcher: some View {
        HStack(spacing: 4) {
            ForEach(AnalyticsComparisonScope.allCases) { scope in
                Button {
                    viewModel.selectedScope = scope
                } label: {
                    Text(scope.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(viewModel.selectedScope == scope ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            Capsule(style: .continuous)
                                .fill(scopeBackground(for: scope))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(scopeBorder(for: scope), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            Capsule(style: .continuous)
                .fill(DesignSystem.Colors.inputBackground(colorScheme))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private var dashboardToolbarActions: some View {
        dashboardToolbarButton(
            title: "Cycles & Goals",
            systemImage: "arrow.triangle.branch",
            accent: true
        ) {
            showingSearchCycleSheet = true
        }
    }

    private func dashboardToolbarButton(
        title: String,
        systemImage: String,
        accent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(accent ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent ? DesignSystem.Colors.accent : DesignSystem.Colors.inputBackground(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(accent ? DesignSystem.Colors.accent.opacity(0.45) : DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func scopeBackground(for scope: AnalyticsComparisonScope) -> AnyShapeStyle {
        if viewModel.selectedScope == scope {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [
                        DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.82 : 0.92),
                        DesignSystem.Colors.accent
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }

        return AnyShapeStyle(Color.clear)
    }

    private func scopeBorder(for scope: AnalyticsComparisonScope) -> Color {
        viewModel.selectedScope == scope
            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.65 : 0.4)
            : .clear
    }

    private func cycleStatsBar(cycle: JobSearchCycle) -> some View {
        let apps = cycle.applications ?? []
        let total = apps.count
        let applied = apps.filter { $0.status == .applied }.count
        let interviewing = apps.filter { $0.status == .interviewing }.count
        let offered = apps.filter { $0.status == .offered }.count
        let saved = apps.filter { $0.status == .saved }.count

        return HStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)

                Text(cycle.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text("ACTIVE")
                    .font(.system(size: 9, weight: .bold))
                    .kerning(0.6)
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.green.opacity(colorScheme == .dark ? 0.16 : 0.10)))
            }
            .frame(minWidth: 140, alignment: .leading)

            StatDivider()

            cycleStatPill(value: "\(total)", label: "In Pipeline", icon: "tray.full", color: DesignSystem.Colors.accent)
            StatDivider()
            cycleStatPill(value: "\(saved)", label: "Saved", icon: "bookmark", color: ApplicationStatus.saved.color)
            StatDivider()
            cycleStatPill(value: "\(applied)", label: "Applied", icon: "paperplane", color: ApplicationStatus.applied.color)
            StatDivider()
            cycleStatPill(value: "\(interviewing)", label: "Interviewing", icon: "person.2", color: ApplicationStatus.interviewing.color)
            StatDivider()
            cycleStatPill(value: "\(offered)", label: "Offered", icon: "gift", color: ApplicationStatus.offered.color)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func cycleStatPill(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(color)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
    }

    private func overviewSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 20) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Performance Snapshot")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            Text(overviewHeadline(for: analytics))
                                .font(.title2.weight(.bold))

                            Text(overviewSubheadline(for: analytics))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: 620, alignment: .leading)
                        }

                        Spacer(minLength: 12)

                        overviewSpotlightCard(analytics: analytics)
                            .frame(maxWidth: 290)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Performance Snapshot")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)

                            Text(overviewHeadline(for: analytics))
                                .font(.title2.weight(.bold))

                            Text(overviewSubheadline(for: analytics))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        overviewSpotlightCard(analytics: analytics)
                    }
                }

                summaryCards
            }
        }
    }

    private func overviewHeadline(for analytics: DashboardAnalyticsResult) -> String {
        if analytics.currentSnapshot.offeredApplications > 0 {
            return "\(analytics.currentSnapshot.offeredApplications) offer\(analytics.currentSnapshot.offeredApplications == 1 ? "" : "s") currently in play."
        }

        if analytics.currentSnapshot.interviewingApplications > 0 {
            return "\(analytics.currentSnapshot.interviewingApplications) interview-stage application\(analytics.currentSnapshot.interviewingApplications == 1 ? "" : "s") active \(analytics.comparisonLabel)."
        }

        if analytics.currentSnapshot.submittedApplications > 0 {
            return "\(analytics.currentSnapshot.submittedApplications) submitted application\(analytics.currentSnapshot.submittedApplications == 1 ? "" : "s") in the current window."
        }

        return "No pipeline movement in the current analytics window yet."
    }

    private func overviewSubheadline(for analytics: DashboardAnalyticsResult) -> String {
        var parts: [String] = [checklistDeltaSummary(analytics)]

        if let activeCycle = analytics.activeCycle {
            parts.append("Active cycle: \(activeCycle.name).")
        } else {
            parts.append("No active search cycle is selected.")
        }

        return parts.joined(separator: " ")
    }

    private func overviewSpotlightCard(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Search Pulse")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            Text(viewModel.percentString(analytics.currentSnapshot.responseRate))
                .font(.system(size: 34, weight: .bold, design: .rounded))

            Text("Response rate across submitted applications")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                overviewMetricPill(
                    title: "Interviews",
                    value: "\(analytics.currentSnapshot.interviewingApplications)",
                    tint: .orange
                )
                overviewMetricPill(
                    title: "Offers",
                    value: "\(analytics.currentSnapshot.offeredApplications)",
                    tint: .green
                )
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.12 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.accent.opacity(0.22), lineWidth: 1)
        )
    }

    private func overviewMetricPill(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.25), lineWidth: 1)
        )
    }

    private var summaryCards: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 240), spacing: 14)], spacing: 14) {
            ForEach(viewModel.summaryCards) { card in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.14 : 0.10))
                            Image(systemName: card.icon)
                                .foregroundColor(DesignSystem.Colors.accent)
                        }
                        .frame(width: 34, height: 34)

                        Spacer()

                        Text(card.deltaText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(deltaColor(named: card.deltaColorName))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(deltaColor(named: card.deltaColorName).opacity(colorScheme == .dark ? 0.14 : 0.10))
                            )
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(card.value)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                        Text(card.title)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.86 : 0.98))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                )
            }
        }
    }

    private func dashboardContent(analytics: DashboardAnalyticsResult) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 16) {
                    funnelSection(analytics: analytics)
                    salarySection(analytics: analytics)
                    timeInStageSection(analytics: analytics)
                }
                .frame(maxWidth: .infinity, alignment: .top)

                VStack(spacing: 16) {
                    ratesSection(analytics: analytics)
                    referralSection(analytics: analytics)
                    rejectionSection(analytics: analytics)
                    goalTrackingSection(analytics: analytics)
                    checklistSection(analytics: analytics)
                    cadenceHeatmapSection(analytics: analytics)
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }

            VStack(spacing: 16) {
                funnelSection(analytics: analytics)
                ratesSection(analytics: analytics)
                referralSection(analytics: analytics)
                rejectionSection(analytics: analytics)
                goalTrackingSection(analytics: analytics)
                checklistSection(analytics: analytics)
                salarySection(analytics: analytics)
                cadenceHeatmapSection(analytics: analytics)
                timeInStageSection(analytics: analytics)
            }
        }
    }

    private func checklistSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Checklist Performance",
                    systemImage: "checklist",
                    eyebrow: "Execution",
                    trailingText: viewModel.percentString(analytics.currentChecklist.completionRate)
                )

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    checklistMetricCard(
                        title: "Completed",
                        value: "\(analytics.currentChecklist.completedItems) / \(analytics.currentChecklist.totalItems)",
                        subtitle: analytics.comparisonLabel,
                        tint: DesignSystem.Colors.accent
                    )
                    checklistMetricCard(
                        title: "Open",
                        value: "\(analytics.currentChecklist.openItems)",
                        subtitle: "Checklist items in scope",
                        tint: .orange
                    )
                    checklistMetricCard(
                        title: "Overdue",
                        value: "\(analytics.currentChecklist.overdueItems)",
                        subtitle: "Past due and incomplete",
                        tint: .red
                    )
                }

                Text(checklistDeltaSummary(analytics))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private func checklistMetricCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Capsule(style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 36, height: 6)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func checklistDeltaSummary(_ analytics: DashboardAnalyticsResult) -> String {
        let current = Int((analytics.currentChecklist.completionRate * 100).rounded())
        let previous = Int((analytics.previousChecklist.completionRate * 100).rounded())
        let delta = current - previous

        if delta == 0 {
            return "Checklist completion is unchanged \(analytics.comparisonLabel)."
        }

        let direction = delta > 0 ? "up" : "down"
        return "Checklist completion is \(direction) by \(abs(delta)) pts \(analytics.comparisonLabel)."
    }

    private func goalTrackingSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Goal Tracking",
                    systemImage: "target",
                    eyebrow: "Progress",
                    trailingText: analytics.activeCycle?.name ?? "No active cycle"
                )

                if analytics.goalProgress.isEmpty {
                    dashboardEmptyState(
                        title: analytics.activeCycle == nil ? "No active cycle" : "No goals yet",
                        systemImage: "target",
                        message: analytics.activeCycle == nil
                            ? "Start or activate a search cycle before tracking weekly or monthly goals."
                            : "Create weekly or monthly goals for the active search cycle to make this dashboard actionable.",
                        actionTitle: analytics.activeCycle == nil ? "Manage Cycles" : "Create Goals"
                    ) {
                        showingSearchCycleSheet = true
                    }
                } else {
                    ForEach(analytics.goalProgress) { progress in
                        let completion = min(Double(progress.progress), Double(progress.target)) / Double(progress.target)

                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .center) {
                                Label(progress.title, systemImage: progress.metric.icon)
                                    .font(.subheadline.weight(.semibold))

                                Spacer()

                                Text("\(progress.progress) / \(progress.target)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.secondary)
                            }

                            ProgressView(value: completion)
                                .tint(DesignSystem.Colors.accent)

                            HStack {
                                Text(progress.periodLabel)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Text(viewModel.percentString(completion))
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(DesignSystem.Colors.accent)
                            }
                        }
                        .padding(16)
                        .background(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    private func cadenceHeatmapSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Application Cadence",
                    systemImage: "calendar",
                    eyebrow: "Rhythm",
                    trailingText: "Last 12 weeks"
                )

                if analytics.cadenceHeatmap.isEmpty {
                    dashboardEmptyState(
                        title: "No application activity yet",
                        systemImage: "calendar.badge.exclamationmark",
                        message: "Submitted applications in the current scope will appear here as a weekly activity pattern."
                    )
                } else {
                    CadenceHeatmapView(cells: analytics.cadenceHeatmap)
                }
            }
        }
    }

    private func salarySection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Salary Analytics",
                    systemImage: "banknote",
                    eyebrow: "Compensation",
                    trailingText: settingsViewModel.analyticsBaseCurrency.rawValue
                )

                if analytics.salaryDistribution.isEmpty && analytics.averageExpectedComp == nil && analytics.averageOfferedComp == nil {
                    dashboardEmptyState(
                        title: "No compensation analytics yet",
                        systemImage: "chart.bar.xaxis",
                        message: "Add posted, expected, or offer compensation to applications in this scope to build salary benchmarks."
                    )
                } else {
                    if !analytics.salaryDistribution.isEmpty {
                        Chart(analytics.salaryDistribution) { bin in
                            BarMark(
                                x: .value("Range", bin.label),
                                y: .value("Applications", bin.count)
                            )
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [
                                        DesignSystem.Colors.accent.opacity(0.7),
                                        DesignSystem.Colors.accent
                                    ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .cornerRadius(5)
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { value in
                                AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                                    .foregroundStyle(Color.secondary.opacity(0.16))
                                AxisValueLabel()
                            }
                        }
                        .chartXAxis {
                            AxisMarks { _ in
                                AxisValueLabel()
                            }
                        }
                        .chartPlotStyle { plot in
                            plot
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
                                )
                        }
                        .frame(height: 240)
                    }

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) {
                            salarySummaryCard(
                                title: "Average Expected",
                                value: analytics.averageExpectedComp.map {
                                    viewModel.currencyString($0, currency: settingsViewModel.analyticsBaseCurrency)
                                } ?? "—",
                                icon: "flag.fill"
                            )

                            salarySummaryCard(
                                title: "Average Offered",
                                value: analytics.averageOfferedComp.map {
                                    viewModel.currencyString($0, currency: settingsViewModel.analyticsBaseCurrency)
                                } ?? "—",
                                icon: "gift.fill"
                            )
                        }

                        VStack(spacing: 12) {
                            salarySummaryCard(
                                title: "Average Expected",
                                value: analytics.averageExpectedComp.map {
                                    viewModel.currencyString($0, currency: settingsViewModel.analyticsBaseCurrency)
                                } ?? "—",
                                icon: "flag.fill"
                            )

                            salarySummaryCard(
                                title: "Average Offered",
                                value: analytics.averageOfferedComp.map {
                                    viewModel.currencyString($0, currency: settingsViewModel.analyticsBaseCurrency)
                                } ?? "—",
                                icon: "gift.fill"
                            )
                        }
                    }
                }
            }
        }
    }

    private func salarySummaryCard(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func funnelSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Application Funnel",
                    systemImage: "chart.bar.fill",
                    eyebrow: "Outcomes",
                    trailingText: analytics.comparisonLabel.capitalized
                )

                Chart(analytics.funnel) { item in
                    BarMark(
                        x: .value("Status", item.status.displayName),
                        y: .value("Count", item.count)
                    )
                    .foregroundStyle(item.status.color.gradient)
                    .cornerRadius(5)
                    .annotation(position: .top) {
                        if item.count > 0 {
                            Text("\(item.count)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(Color.secondary.opacity(0.16))
                        AxisValueLabel()
                    }
                }
                .chartPlotStyle { plot in
                    plot
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
                        )
                }
                .frame(height: 240)
            }
        }
    }

    private func timeInStageSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Average Time in Stage",
                    systemImage: "clock.fill",
                    eyebrow: "Cycle Friction",
                    trailingText: analytics.timeInStage.isEmpty ? nil : "Average days"
                )

                if analytics.timeInStage.isEmpty {
                    dashboardEmptyState(
                        title: "Not enough timing data yet",
                        systemImage: "clock.badge.questionmark",
                        message: "Stage timing appears once enough in-scope applications move through the pipeline."
                    )
                } else {
                    Chart(analytics.timeInStage) { item in
                        BarMark(
                            x: .value("Days", item.averageDays),
                            y: .value("Stage", item.status.displayName)
                        )
                        .foregroundStyle(item.status.color.gradient)
                        .cornerRadius(5)
                        .annotation(position: .trailing) {
                            Text("\(Int(item.averageDays.rounded()))d")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                                .foregroundStyle(Color.secondary.opacity(0.14))
                            AxisValueLabel()
                        }
                    }
                    .chartPlotStyle { plot in
                        plot
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
                            )
                    }
                    .frame(height: CGFloat(analytics.timeInStage.count) * 52 + 20)
                }
            }
        }
    }

    private func ratesSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Conversion Rates",
                    systemImage: "percent",
                    eyebrow: "Efficiency",
                    trailingText: analytics.comparisonLabel.capitalized
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        rateGauge(label: "Response", value: analytics.currentSnapshot.responseRate, color: .green)
                        rateGauge(
                            label: "Interview",
                            value: analytics.currentSnapshot.submittedApplications == 0
                                ? 0
                                : Double(analytics.currentSnapshot.interviewingApplications) / Double(analytics.currentSnapshot.submittedApplications),
                            color: .orange
                        )
                        rateGauge(
                            label: "Offer",
                            value: analytics.currentSnapshot.submittedApplications == 0
                                ? 0
                                : Double(analytics.currentSnapshot.offeredApplications) / Double(analytics.currentSnapshot.submittedApplications),
                            color: .purple
                        )
                    }

                    VStack(spacing: 12) {
                        rateGauge(label: "Response", value: analytics.currentSnapshot.responseRate, color: .green)
                        rateGauge(
                            label: "Interview",
                            value: analytics.currentSnapshot.submittedApplications == 0
                                ? 0
                                : Double(analytics.currentSnapshot.interviewingApplications) / Double(analytics.currentSnapshot.submittedApplications),
                            color: .orange
                        )
                        rateGauge(
                            label: "Offer",
                            value: analytics.currentSnapshot.submittedApplications == 0
                                ? 0
                                : Double(analytics.currentSnapshot.offeredApplications) / Double(analytics.currentSnapshot.submittedApplications),
                            color: .purple
                        )
                    }
                }
            }
        }
    }

    private func referralSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Referral Tracker",
                    systemImage: "person.3.fill",
                    eyebrow: "Network",
                    trailingText: viewModel.percentString(analytics.referralSummary.interviewReferralRate)
                )

                Text("\(analytics.referralSummary.interviewingApplicationsWithReferral) of \(analytics.currentSnapshot.interviewingApplications) interview tracks came from received referrals.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    dashboardMetricPill(
                        title: "Referred Apps",
                        value: "\(analytics.referralSummary.applicationsWithReceivedReferral)",
                        icon: "briefcase.fill",
                        tint: .green
                    )
                    dashboardMetricPill(
                        title: "Interview Wins",
                        value: "\(analytics.referralSummary.interviewingApplicationsWithReferral)",
                        icon: "bubble.left.and.bubble.right.fill",
                        tint: .blue
                    )
                    dashboardMetricPill(
                        title: "Received Referrals",
                        value: "\(analytics.referralSummary.receivedReferralAttempts)",
                        icon: "checkmark.circle.fill",
                        tint: .orange
                    )
                    dashboardMetricPill(
                        title: "Conversion",
                        value: viewModel.percentString(analytics.referralSummary.interviewReferralRate),
                        icon: "chart.line.uptrend.xyaxis",
                        tint: .purple
                    )
                }
            }
        }
    }

    private func dashboardMetricPill(title: String, value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundColor(tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline.weight(.semibold))
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.08))
        )
    }

    private func rejectionSection(analytics: DashboardAnalyticsResult) -> some View {
        dashboardSectionCard {
            VStack(alignment: .leading, spacing: 16) {
                dashboardSectionHeader(
                    title: "Rejection Learnings",
                    systemImage: "arrow.counterclockwise.circle",
                    eyebrow: "Learning Loop",
                    trailingText: analytics.rejectionSummary.hasFreshInsights ? "AI-ready" : "Capture more data"
                )

                if analytics.rejectionSummary.rejectedApplications == 0 {
                    dashboardEmptyState(
                        title: "No rejected applications in scope",
                        systemImage: "checkmark.circle",
                        message: "Rejection learnings appear once rejected applications enter the current analytics window."
                    )
                } else if analytics.rejectionSummary.loggedRejections < 3 {
                    VStack(alignment: .leading, spacing: 12) {
                        rejectionMetricRow(
                            title: "Logged Rejections",
                            value: "\(analytics.rejectionSummary.loggedRejections)",
                            subtitle: "\(analytics.rejectionSummary.missingLogCount) missing structured logs"
                        )

                        Text("Capture at least 3 rejection logs to unlock higher-confidence pattern analysis.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else if analytics.rejectionSummary.hasFreshInsights {
                    VStack(alignment: .leading, spacing: 12) {
                        rejectionMetricRow(
                            title: "Logged Rejections",
                            value: "\(analytics.rejectionSummary.loggedRejections)",
                            subtitle: analytics.rejectionSummary.missingLogCount == 0
                                ? "All rejected applications are logged"
                                : "\(analytics.rejectionSummary.missingLogCount) missing structured logs"
                        )

                        if let topSignal = analytics.rejectionSummary.topSignal {
                            insightCard(title: "Pattern", body: topSignal)
                        }

                        if let suggestion = analytics.rejectionSummary.topRecoverySuggestion {
                            insightCard(title: "Recovery", body: suggestion)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        rejectionMetricRow(
                            title: "Logged Rejections",
                            value: "\(analytics.rejectionSummary.loggedRejections)",
                            subtitle: "Waiting for a fresh AI analysis snapshot"
                        )

                        Text("Your rejection logs are captured, but the latest AI learnings are stale or missing.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func rejectionMetricRow(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3.weight(.bold))
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func insightCard(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(body)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func rateGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.16), lineWidth: 10)

                Circle()
                    .trim(from: 0, to: max(0, min(value, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                VStack(spacing: 2) {
                    Text(viewModel.percentString(value))
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 88, height: 88)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProgressView()

            Text("Refreshing analytics")
                .font(.title3.weight(.semibold))

            Text("Recomputing search momentum, conversion rates, and dashboard benchmarks.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let onboardingProgress, onboardingProgress.shouldShowSetupGuidance, let onOnboardingAction {
                OnboardingChecklistCard(
                    title: "Finish Core Setup",
                    progress: onboardingProgress,
                    onAction: onOnboardingAction,
                    onMute: onHideOnboardingGuidance
                )
            }

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text("No analytics yet")
                        .font(.title3.weight(.semibold))
                    Text("Add applications or create a search cycle to populate the dashboard with real momentum, goals, and conversion data.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                if let onOnboardingAction {
                    dashboardToolbarButton(
                        title: "Add Application",
                        systemImage: "plus.circle.fill",
                        accent: true
                    ) {
                        onOnboardingAction(.addApplication)
                    }
                }

                dashboardToolbarButton(
                    title: "Cycles & Goals",
                    systemImage: "arrow.triangle.branch",
                    accent: true
                ) {
                    showingSearchCycleSheet = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(28)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private func dashboardSectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.surfaceElevated(colorScheme),
                                DesignSystem.Colors.surface(colorScheme)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
            )
    }

    private func dashboardSectionHeader(
        title: String,
        systemImage: String,
        eyebrow: String,
        trailingText: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Label(title, systemImage: systemImage)
                    .font(.headline)
            }

            Spacer()

            if let trailingText {
                Text(trailingText)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule(style: .continuous)
                            .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.80 : 0.96))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                    )
            }
        }
    }

    private func dashboardEmptyState(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.title3.weight(.semibold))

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme).opacity(colorScheme == .dark ? 0.82 : 0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func deltaColor(named name: String) -> Color {
        switch name {
        case "positive":
            return .green
        case "negative":
            return .red
        default:
            return .secondary
        }
    }
}

private struct CadenceHeatmapView: View {
    @Environment(\.colorScheme) private var colorScheme

    let cells: [DashboardHeatmapCell]

    private let weekdayLabels = Calendar.current.shortStandaloneWeekdaySymbols

    private var grouped: [(week: Date, cells: [DashboardHeatmapCell])] {
        Dictionary(grouping: cells, by: \.weekStart)
            .map { key, value in
                (week: key, cells: value.sorted { $0.weekdayIndex < $1.weekdayIndex })
            }
            .sorted { $0.week < $1.week }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Activity density")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Text("Quiet")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    ForEach(0..<4, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(heatColor(for: level))
                            .frame(width: 14, height: 14)
                    }

                    Text("Active")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(0..<7, id: \.self) { index in
                        Text(weekdayLabels[index])
                            .font(.caption2.weight(.medium))
                            .foregroundColor(.secondary)
                            .frame(width: 28, height: 20, alignment: .leading)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(grouped, id: \.week) { column in
                            VStack(spacing: 8) {
                                ForEach(column.cells) { cell in
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(heatColor(for: cell.count))
                                        .frame(width: 20, height: 20)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.white.opacity(colorScheme == .dark ? 0.06 : 0.10), lineWidth: 1)

                                            if cell.count > 0 {
                                                Text("\(cell.count)")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                }

                                VStack(spacing: 1) {
                                    Text(column.week, format: .dateTime.month(.abbreviated))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(.secondary)
                                    Text(column.week, format: .dateTime.day())
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 28)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func heatColor(for count: Int) -> Color {
        switch count {
        case 0:
            return DesignSystem.Colors.inputBackground(colorScheme)
        case 1:
            return DesignSystem.Colors.accent.opacity(0.35)
        case 2:
            return DesignSystem.Colors.accent.opacity(0.55)
        case 3:
            return DesignSystem.Colors.accent.opacity(0.75)
        default:
            return DesignSystem.Colors.accent
        }
    }
}

// MARK: - Search Cycle Sheet

private struct SearchCycleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \JobSearchCycle.startDate, order: .reverse) private var cycles: [JobSearchCycle]

    // Create-cycle form
    @State private var newCycleName = ""
    @State private var newCycleStartDate = Date()

    // Goal form
    @State private var selectedMetric: SearchGoalMetric = .applicationsSubmitted
    @State private var selectedCadence: SearchGoalCadence = .weekly
    @State private var targetValue = ""
    @State private var editingGoal: SearchGoal?

    // Import picker
    @State private var showImportPicker = false
    @State private var importSourceCycle: JobSearchCycle?
    @State private var importTargetCycle: JobSearchCycle?
    @State private var selectedAppIDs: Set<UUID> = []

    // Confirmations & errors
    @State private var errorMessage: String?
    @State private var cycleToDelete: JobSearchCycle?
    @State private var showDeleteConfirmation = false

    private var activeCycle: JobSearchCycle? {
        cycles.first(where: \.isActive)
    }

    var body: some View {
        NavigationStack {
            #if os(macOS)
            VStack(spacing: 0) {
                macHeader

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                ScrollView {
                    modalContent
                        .padding(24)
                }

                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                macFooter
            }
            .frame(minWidth: 760, idealWidth: 820, minHeight: 650, idealHeight: 720)
            .background(DesignSystem.Colors.contentBackground(colorScheme))
            #else
            ScrollView {
                modalContent
                    .padding(16)
            }
            .background(DesignSystem.Colors.contentBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("Search Cycles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
        .alert("Action Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "An unknown error occurred.")
        }
        .sheet(isPresented: $showImportPicker) {
            ApplicationImportPicker(
                targetCycle: importTargetCycle,
                sourceCycle: importSourceCycle,
                selectedAppIDs: $selectedAppIDs,
                onImport: { importApplications() },
                onCancel: { resetImportState() }
            )
        }
        .confirmationDialog(
            "Delete Cycle?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                if let cycle = cycleToDelete { deleteCycle(cycle) }
            }
            Button("Cancel", role: .cancel) { cycleToDelete = nil }
        } message: {
            if let cycle = cycleToDelete {
                Text("This will permanently remove \"\(cycle.name)\". Its \(cycle.applications?.count ?? 0) application(s) will become unlinked.")
            }
        }
    }

    // MARK: - Modal Content

    private var modalContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            heroCard
            newCycleCard
            if activeCycle != nil {
                goalsCard
            }
            allCyclesCard
        }
    }

    // MARK: - Hero Card

    private var heroCard: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 58, height: 58)

                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(activeCycle?.name ?? "No Active Cycle")
                        .font(.title3.weight(.semibold))

                    Text(activeCycle != nil ? "ACTIVE" : "NONE")
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.8)
                        .foregroundColor(activeCycle != nil ? .green : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(
                                    (activeCycle != nil ? Color.green : Color.secondary)
                                        .opacity(colorScheme == .dark ? 0.16 : 0.10)
                                )
                        )
                }

                if let cycle = activeCycle {
                    Text("Started \(cycle.startDate.formatted(date: .abbreviated, time: .omitted)) \u{00B7} \(cycleDurationText(cycle)) \u{00B7} \(applicationCount(for: cycle)) applications \u{00B7} \(activeGoalCount(cycle)) goals")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Start or activate a search cycle to begin tracking your job search progress.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    // MARK: - New Cycle Card

    private var newCycleCard: some View {
        sectionCard(
            title: "New Cycle",
            icon: "plus.circle",
            description: "Start a new search cycle. The previous active cycle will be deactivated automatically."
        ) {
            #if os(macOS)
            let columns = [
                GridItem(.flexible(), spacing: 14, alignment: .top),
                GridItem(.flexible(), spacing: 14, alignment: .top)
            ]
            #else
            let columns = [GridItem(.flexible(), spacing: 14, alignment: .top)]
            #endif

            LazyVGrid(columns: columns, spacing: 14) {
                fieldSurface(title: "Cycle Name", caption: "A memorable label for this search phase.") {
                    TextField("e.g. Q2 2026 Search", text: $newCycleName)
                        .textFieldStyle(.plain)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appInput()
                }

                fieldSurface(title: "Start Date", caption: "When this search phase begins.") {
                    DatePicker("", selection: $newCycleStartDate, displayedComponents: .date)
                        .labelsHidden()
                        #if os(macOS)
                        .datePickerStyle(.compact)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appInput()
                }
            }

            if activeCycle != nil {
                banner(
                    text: "Starting a new cycle will deactivate \"\(activeCycle!.name)\". You\u{2019}ll be able to carry over in-progress applications.",
                    systemImage: "exclamationmark.triangle",
                    tint: .orange
                )
            }

            HStack {
                Spacer()
                Button("Start Cycle") { handleStartCycle() }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .controlSize(.large)
                    .disabled(newCycleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    // MARK: - Goals Card

    private var goalsCard: some View {
        sectionCard(
            title: editingGoal == nil ? "Goals" : "Edit Goal",
            icon: "target",
            description: "Set weekly or monthly targets for the active cycle to keep your search accountable."
        ) {
            #if os(macOS)
            let columns = [
                GridItem(.flexible(), spacing: 14, alignment: .top),
                GridItem(.flexible(), spacing: 14, alignment: .top),
                GridItem(.flexible(), spacing: 14, alignment: .top)
            ]
            #else
            let columns = [GridItem(.flexible(), spacing: 14, alignment: .top)]
            #endif

            LazyVGrid(columns: columns, spacing: 14) {
                fieldSurface(title: "Metric") {
                    Picker("", selection: $selectedMetric) {
                        ForEach(SearchGoalMetric.allCases) { metric in
                            Label(metric.displayName, systemImage: metric.icon).tag(metric)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }

                fieldSurface(title: "Cadence") {
                    Picker("", selection: $selectedCadence) {
                        ForEach(SearchGoalCadence.allCases) { cadence in
                            Text(cadence.displayName).tag(cadence)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appInput()
                }

                fieldSurface(title: "Target") {
                    TextField("e.g. 10", text: $targetValue)
                        .textFieldStyle(.plain)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appInput()
                }
            }

            HStack {
                if editingGoal != nil {
                    Button("Cancel Edit") { resetGoalForm() }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                }
                Spacer()
                Button(editingGoal == nil ? "Add Goal" : "Update Goal") {
                    if let cycle = activeCycle {
                        saveGoal(for: cycle)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .controlSize(.regular)
                .disabled(Int(targetValue) == nil || (Int(targetValue) ?? 0) <= 0)
            }

            if let cycle = activeCycle, !cycle.sortedGoals.isEmpty {
                Divider().overlay(DesignSystem.Colors.divider(colorScheme))

                ForEach(cycle.sortedGoals) { goal in
                    goalRow(goal)
                }
            }
        }
    }

    // MARK: - All Cycles Card

    private var allCyclesCard: some View {
        sectionCard(
            title: "All Cycles",
            icon: "clock.arrow.circlepath",
            description: "Your search history. Activate a past cycle or remove cycles you no longer need."
        ) {
            if cycles.isEmpty {
                banner(
                    text: "No cycles yet. Create your first cycle above to start tracking your job search.",
                    systemImage: "lightbulb",
                    tint: .orange
                )
            } else {
                ForEach(cycles) { cycle in
                    cycleRow(cycle)
                }
            }
        }
    }

    // MARK: - Row Views

    private func cycleRow(_ cycle: JobSearchCycle) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(cycle.isActive ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 3) {
                Text(cycle.name)
                    .font(.subheadline.weight(.semibold))
                Text(cycleDateText(for: cycle))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "doc.text")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("\(applicationCount(for: cycle))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Text(cycle.isActive ? "ACTIVE" : (cycle.endDate != nil ? "ENDED" : "INACTIVE"))
                .font(.system(size: 10, weight: .semibold))
                .kerning(0.6)
                .foregroundColor(cycle.isActive ? .green : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(
                            (cycle.isActive ? Color.green : Color.secondary)
                                .opacity(colorScheme == .dark ? 0.16 : 0.10)
                        )
                )

            HStack(spacing: 6) {
                if !cycle.isActive {
                    Button {
                        activate(cycle)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .fastTooltip("Activate this cycle")
                    .interactiveHandCursor()
                }

                if cycle.isActive {
                    Button {
                        end(cycle)
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .frame(width: 28, height: 28)
                            .background(
                                Circle()
                                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                            )
                    }
                    .buttonStyle(.plain)
                    .fastTooltip("End this cycle")
                    .interactiveHandCursor()
                }

                Button {
                    importTargetCycle = cycle
                    importSourceCycle = nil
                    selectedAppIDs = []
                    showImportPicker = true
                } label: {
                    Image(systemName: "square.and.arrow.down.on.square")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.accent)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .fastTooltip("Import applications")
                .interactiveHandCursor()

                Button {
                    cycleToDelete = cycle
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundColor(DesignSystem.Colors.destructive(colorScheme))
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(DesignSystem.Colors.destructive(colorScheme).opacity(colorScheme == .dark ? 0.18 : 0.12))
                        )
                }
                .buttonStyle(.plain)
                .fastTooltip("Delete this cycle")
                .interactiveHandCursor()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    cycle.isActive ? Color.green.opacity(0.4) : DesignSystem.Colors.stroke(colorScheme),
                    lineWidth: cycle.isActive ? 1.5 : 1
                )
        )
    }

    private func goalRow(_ goal: SearchGoal) -> some View {
        HStack(spacing: 12) {
            Image(systemName: goal.metric.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(goal.isArchived ? .secondary : DesignSystem.Colors.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(goal.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(goal.isArchived ? .secondary : .primary)
                Text("\(goal.targetValue) per \(goal.cadence.displayName.lowercased())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if goal.isArchived {
                Text("ARCHIVED")
                    .font(.system(size: 10, weight: .semibold))
                    .kerning(0.6)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule(style: .continuous).fill(Color.secondary.opacity(0.12)))
            }

            Button {
                editGoal(goal)
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(DesignSystem.Colors.surfaceElevated(colorScheme)))
            }
            .buttonStyle(.plain)
            .fastTooltip("Edit goal")
            .interactiveHandCursor()

            Button {
                toggleArchive(goal)
            } label: {
                Image(systemName: goal.isArchived ? "arrow.uturn.backward" : "archivebox")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(DesignSystem.Colors.surfaceElevated(colorScheme)))
            }
            .buttonStyle(.plain)
            .fastTooltip(goal.isArchived ? "Restore goal" : "Archive goal")
            .interactiveHandCursor()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    // MARK: - macOS Header & Footer

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Search Cycles")
                    .font(.title3.weight(.semibold))

                Text("Manage cycles and goals for your job search")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var macFooter: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.triangle.branch")
                    .foregroundColor(DesignSystem.Colors.accent)

                Text(activeCycle != nil ? "Active: \(activeCycle!.name)" : "No active cycle")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Done") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
    #endif

    // MARK: - Helpers

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: icon)
                    .font(.headline)

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func fieldSurface<Content: View>(
        title: String,
        caption: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundColor(.secondary)

            content()

            if let caption {
                Text(caption)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 20, alignment: .center)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(colorScheme == .dark ? 0.25 : 0.15), lineWidth: 1)
        )
    }

    // MARK: - Computed Properties

    private func cycleDurationText(_ cycle: JobSearchCycle) -> String {
        let end = cycle.endDate ?? Date()
        let days = max(1, Calendar.current.dateComponents([.day], from: cycle.startDate, to: end).day ?? 1)
        return "\(days) day\(days == 1 ? "" : "s")"
    }

    private func activeGoalCount(_ cycle: JobSearchCycle) -> Int {
        (cycle.goals ?? []).filter { !$0.isArchived }.count
    }

    private func applicationCount(for cycle: JobSearchCycle) -> Int {
        let direct = cycle.applications?.count ?? 0
        guard !cycle.isActive else { return direct }
        let originated = cycles
            .filter { $0.id != cycle.id }
            .flatMap { $0.applications ?? [] }
            .filter { $0.originCycle?.id == cycle.id }
            .count
        return direct + originated
    }

    private func cycleDateText(for cycle: JobSearchCycle) -> String {
        let start = cycle.startDate.formatted(date: .abbreviated, time: .omitted)
        if let endDate = cycle.endDate {
            return "\(start) \u{2013} \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Started \(start)"
    }

    // MARK: - Actions

    private func handleStartCycle() {
        let outgoing = activeCycle
        guard let newCycle = createCycle() else { return }

        if let outgoing, hasEligibleApps(in: outgoing) {
            importSourceCycle = outgoing
            importTargetCycle = newCycle
            selectedAppIDs = preSelectedAppIDs(from: outgoing)
            showImportPicker = true
        }
    }

    @discardableResult
    private func createCycle() -> JobSearchCycle? {
        do {
            let cycle = JobSearchCycle(
                name: newCycleName.trimmingCharacters(in: .whitespacesAndNewlines),
                startDate: newCycleStartDate,
                isActive: true
            )
            for existing in cycles where existing.isActive {
                existing.isActive = false
                existing.updateTimestamp()
            }
            modelContext.insert(cycle)
            try modelContext.save()
            newCycleName = ""
            newCycleStartDate = Date()
            return cycle
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func hasEligibleApps(in cycle: JobSearchCycle) -> Bool {
        (cycle.applications ?? []).contains { !isTerminalStatus($0.status) }
    }

    private func isTerminalStatus(_ status: ApplicationStatus) -> Bool {
        status == .rejected || status == .archived
    }

    private func preSelectedAppIDs(from cycle: JobSearchCycle) -> Set<UUID> {
        let eligible = (cycle.applications ?? []).filter { app in
            let s = app.status
            return s == .saved || s == .applied || s == .interviewing
        }
        return Set(eligible.map(\.id))
    }

    private func importApplications() {
        guard let target = importTargetCycle else { return }
        let allApps: [JobApplication]
        if let source = importSourceCycle {
            allApps = source.applications ?? []
        } else {
            allApps = cycles.flatMap { cycle in
                guard cycle.id != target.id else { return [JobApplication]() }
                return cycle.applications ?? []
            }
        }
        for app in allApps where selectedAppIDs.contains(app.id) {
            app.assignCycle(target)
        }
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
        resetImportState()
    }

    private func resetImportState() {
        showImportPicker = false
        importSourceCycle = nil
        importTargetCycle = nil
        selectedAppIDs = []
    }

    private func activate(_ cycle: JobSearchCycle) {
        do {
            try JobSearchCycleMigrationService.activate(cycle, in: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func end(_ cycle: JobSearchCycle) {
        do {
            cycle.end()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCycle(_ cycle: JobSearchCycle) {
        do {
            for app in (cycle.applications ?? []) {
                app.assignCycle(nil)
            }
            for goal in (cycle.goals ?? []) {
                modelContext.delete(goal)
            }
            modelContext.delete(cycle)
            try modelContext.save()
            cycleToDelete = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveGoal(for cycle: JobSearchCycle) {
        guard let target = Int(targetValue), target > 0 else { return }

        do {
            if let editingGoal {
                editingGoal.metric = selectedMetric
                editingGoal.cadence = selectedCadence
                editingGoal.targetValue = target
                editingGoal.updateTimestamp()
            } else {
                let goal = SearchGoal(
                    metric: selectedMetric,
                    cadence: selectedCadence,
                    targetValue: target,
                    cycle: cycle
                )
                modelContext.insert(goal)
            }

            cycle.updateTimestamp()
            try modelContext.save()
            resetGoalForm()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func editGoal(_ goal: SearchGoal) {
        editingGoal = goal
        selectedMetric = goal.metric
        selectedCadence = goal.cadence
        targetValue = String(goal.targetValue)
    }

    private func resetGoalForm() {
        editingGoal = nil
        selectedMetric = .applicationsSubmitted
        selectedCadence = .weekly
        targetValue = ""
    }

    private func toggleArchive(_ goal: SearchGoal) {
        do {
            if goal.isArchived {
                goal.unarchive()
            } else {
                goal.archive()
            }
            goal.cycle?.updateTimestamp()
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Application Import Picker

private struct ApplicationImportPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \JobSearchCycle.startDate, order: .reverse) private var allCycles: [JobSearchCycle]

    let targetCycle: JobSearchCycle?
    let sourceCycle: JobSearchCycle?
    @Binding var selectedAppIDs: Set<UUID>
    let onImport: () -> Void
    let onCancel: () -> Void

    @State private var selectedSourceID: UUID?

    private var isAdHocMode: Bool { sourceCycle == nil }

    private var sourceCycles: [JobSearchCycle] {
        allCycles.filter { $0.id != targetCycle?.id }
    }

    private var resolvedSource: JobSearchCycle? {
        if let sourceCycle { return sourceCycle }
        if let selectedSourceID {
            return allCycles.first { $0.id == selectedSourceID }
        }
        return nil
    }

    private var eligibleApps: [JobApplication] {
        let apps: [JobApplication]
        if let source = resolvedSource {
            apps = source.applications ?? []
        } else if isAdHocMode {
            apps = sourceCycles.flatMap { $0.applications ?? [] }
        } else {
            apps = []
        }
        return apps.filter { !isTerminal($0.status) }
    }

    private var statusGroups: [(status: ApplicationStatus, apps: [JobApplication])] {
        let order: [ApplicationStatus] = [.saved, .applied, .interviewing, .offered]
        var result: [(ApplicationStatus, [JobApplication])] = []

        for status in order {
            let matching = eligibleApps.filter { $0.status == status }
                .sorted { ($0.companyName, $0.role) < ($1.companyName, $1.role) }
            if !matching.isEmpty {
                result.append((status, matching))
            }
        }

        // Custom statuses
        let customApps = eligibleApps.filter {
            if case .custom = $0.status { return true }
            return false
        }.sorted { ($0.companyName, $0.role) < ($1.companyName, $1.role) }

        if !customApps.isEmpty {
            result.append((.custom("Other"), customApps))
        }

        return result
    }

    private func isTerminal(_ status: ApplicationStatus) -> Bool {
        status == .rejected || status == .archived
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            macHeader

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            ScrollView {
                pickerContent
                    .padding(24)
            }

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            macFooter
        }
        .frame(minWidth: 680, idealWidth: 740, minHeight: 520, idealHeight: 620)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        #else
        NavigationStack {
            ScrollView {
                pickerContent
                    .padding(16)
            }
            .background(DesignSystem.Colors.contentBackground(colorScheme).ignoresSafeArea())
            .navigationTitle("Import Applications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onCancel(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import (\(selectedAppIDs.count))") {
                        onImport()
                        dismiss()
                    }
                    .disabled(selectedAppIDs.isEmpty)
                }
            }
        }
        #endif
    }

    // MARK: - Content

    private var pickerContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            moveBanner

            if isAdHocMode {
                sourceFilterCard
            }

            if eligibleApps.isEmpty {
                emptyState
            } else {
                applicationListCard
            }
        }
    }

    private var moveBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.right.doc.on.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DesignSystem.Colors.accent)
                .frame(width: 20, alignment: .center)

            Text("Selected applications will be **moved** to \"\(targetCycle?.name ?? "the target cycle")\". They will no longer appear in their source cycle.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.25 : 0.15), lineWidth: 1)
        )
    }

    private var sourceFilterCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Source", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)

                Text("Choose which cycle to import applications from, or browse all.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Picker("", selection: $selectedSourceID) {
                Text("All Cycles").tag(nil as UUID?)
                ForEach(sourceCycles) { cycle in
                    HStack {
                        Text(cycle.name)
                        if cycle.isActive {
                            Text("(Active)")
                        }
                    }.tag(cycle.id as UUID?)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appInput()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private var applicationListCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Applications", systemImage: "doc.on.doc")
                    .font(.headline)

                Text("\(eligibleApps.count) eligible application\(eligibleApps.count == 1 ? "" : "s"). Rejected and archived applications are excluded.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            ForEach(statusGroups, id: \.status) { group in
                statusGroupView(status: group.status, apps: group.apps)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func statusGroupView(status: ApplicationStatus, apps: [JobApplication]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                StatusBadge(status: status, showIcon: true, size: .small)

                Text("\(apps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                let allSelected = apps.allSatisfy { selectedAppIDs.contains($0.id) }
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        for app in apps { selectedAppIDs.remove(app.id) }
                    } else {
                        for app in apps { selectedAppIDs.insert(app.id) }
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundColor(DesignSystem.Colors.accent)
                .buttonStyle(.plain)
                .interactiveHandCursor()
            }

            ForEach(apps) { app in
                applicationRow(app)
            }
        }
    }

    private func applicationRow(_ app: JobApplication) -> some View {
        let isSelected = selectedAppIDs.contains(app.id)

        return Button {
            if isSelected {
                selectedAppIDs.remove(app.id)
            } else {
                selectedAppIDs.insert(app.id)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : .secondary.opacity(0.5))

                CompanyAvatar(
                    companyName: app.companyName,
                    logoURL: app.googleS2FaviconURL(size: 64)?.absoluteString,
                    size: 34,
                    cornerRadius: 8
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(app.role)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(app.companyName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isAdHocMode, let cycleName = app.cycle?.name {
                    Text(cycleName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                        )
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected
                        ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.10 : 0.05)
                        : Color.clear
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected
                            ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.30 : 0.20)
                            : DesignSystem.Colors.stroke(colorScheme),
                        lineWidth: 1
                    )
            )
        }
        .buttonStyle(.plain)
        .interactiveHandCursor()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundColor(.secondary)

            Text("No eligible applications")
                .font(.subheadline.weight(.medium))

            Text("There are no active applications to import from \(resolvedSource != nil ? "this cycle" : "other cycles").")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    // MARK: - macOS Header & Footer

    #if os(macOS)
    private var macHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Applications")
                    .font(.title3.weight(.semibold))

                Text("Select applications to move into \"\(targetCycle?.name ?? "cycle")\"")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button {
                onCancel()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var macFooter: some View {
        HStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(DesignSystem.Colors.accent)

                Text("\(selectedAppIDs.count) of \(eligibleApps.count) selected")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Cancel") {
                onCancel()
                dismiss()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button("Import \(selectedAppIDs.count) Application\(selectedAppIDs.count == 1 ? "" : "s")") {
                onImport()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
            .disabled(selectedAppIDs.isEmpty)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }
    #endif
}

#Preview {
    DashboardView(settingsViewModel: SettingsViewModel())
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
                FollowUpStep.self,
                ApplicationChecklistSuggestion.self,
                ApplicationAttachment.self,
                CoverLetterDraft.self,
                JobMatchAssessment.self,
                ATSCompatibilityAssessment.self,
                ATSCompatibilityScanRun.self
            ],
            inMemory: true
        )
}
