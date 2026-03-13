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

    @State private var showingCycleManager = false
    @State private var showingGoalManager = false

    let settingsViewModel: SettingsViewModel

    init(settingsViewModel: SettingsViewModel = SettingsViewModel()) {
        self.settingsViewModel = settingsViewModel
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
        .sheet(isPresented: $showingCycleManager) {
            CycleManagementSheet()
        }
        .sheet(isPresented: $showingGoalManager) {
            GoalManagementSheet(activeCycle: viewModel.analytics?.activeCycle)
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
        HStack(spacing: 8) {
            dashboardToolbarButton(
                title: "Cycles",
                systemImage: "arrow.triangle.branch",
                accent: false
            ) {
                showingCycleManager = true
            }

            dashboardToolbarButton(
                title: "Goals",
                systemImage: "target",
                accent: true
            ) {
                showingGoalManager = true
            }
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
                        if analytics.activeCycle == nil {
                            showingCycleManager = true
                        } else {
                            showingGoalManager = true
                        }
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
                    Text("Add a few applications or create a search cycle to populate the dashboard.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                dashboardToolbarButton(
                    title: "Manage Cycles",
                    systemImage: "arrow.triangle.branch",
                    accent: false
                ) {
                    showingCycleManager = true
                }

                dashboardToolbarButton(
                    title: "Create Goals",
                    systemImage: "target",
                    accent: true
                ) {
                    showingGoalManager = true
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

private struct CycleManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobSearchCycle.startDate, order: .reverse) private var cycles: [JobSearchCycle]

    @State private var newCycleName = ""
    @State private var newCycleStartDate = Date()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Start New Cycle") {
                    TextField("Cycle Name", text: $newCycleName)
                    DatePicker("Start Date", selection: $newCycleStartDate, displayedComponents: .date)

                    Button("Start Cycle") {
                        startCycle()
                    }
                    .disabled(newCycleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("Existing Cycles") {
                    ForEach(cycles) { cycle in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(cycle.name)
                                    .font(.headline)
                                if cycle.isActive {
                                    Text("ACTIVE")
                                        .font(.caption2.weight(.bold))
                                        .foregroundColor(.green)
                                }
                                Spacer()
                            }

                            Text(cycleDateText(for: cycle))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack {
                                Button(cycle.isActive ? "Active" : "Activate") {
                                    activate(cycle)
                                }
                                .disabled(cycle.isActive)

                                if cycle.isActive {
                                    Button("End Cycle") {
                                        end(cycle)
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Search Cycles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Cycle Action Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private func startCycle() {
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
        } catch {
            errorMessage = error.localizedDescription
        }
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

    private func cycleDateText(for cycle: JobSearchCycle) -> String {
        let start = cycle.startDate.formatted(date: .abbreviated, time: .omitted)
        if let endDate = cycle.endDate {
            return "\(start) - \(endDate.formatted(date: .abbreviated, time: .omitted))"
        }
        return "Started \(start)"
    }
}

private struct GoalManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let activeCycle: JobSearchCycle?

    @State private var selectedMetric: SearchGoalMetric = .applicationsSubmitted
    @State private var selectedCadence: SearchGoalCadence = .weekly
    @State private var targetValue = ""
    @State private var editingGoal: SearchGoal?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let activeCycle {
                    Section("Active Cycle") {
                        Text(activeCycle.name)
                            .font(.headline)
                    }

                    Section(editingGoal == nil ? "Add Goal" : "Edit Goal") {
                        Picker("Metric", selection: $selectedMetric) {
                            ForEach(SearchGoalMetric.allCases) { metric in
                                Text(metric.displayName).tag(metric)
                            }
                        }

                        Picker("Cadence", selection: $selectedCadence) {
                            ForEach(SearchGoalCadence.allCases) { cadence in
                                Text(cadence.displayName).tag(cadence)
                            }
                        }

                        TextField("Target", text: $targetValue)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif

                        Button(editingGoal == nil ? "Save Goal" : "Update Goal") {
                            saveGoal(for: activeCycle)
                        }
                        .disabled(Int(targetValue) == nil)
                    }

                    Section("Goals") {
                        ForEach(activeCycle.sortedGoals) { goal in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(goal.title, systemImage: goal.metric.icon)
                                    Spacer()
                                    Text(goal.isArchived ? "Archived" : "\(goal.targetValue)")
                                        .foregroundColor(.secondary)
                                }

                                HStack {
                                    Button("Edit") {
                                        editingGoal = goal
                                        selectedMetric = goal.metric
                                        selectedCadence = goal.cadence
                                        targetValue = String(goal.targetValue)
                                    }

                                    Button(goal.isArchived ? "Restore" : "Archive") {
                                        toggleArchive(goal)
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No active cycle",
                        systemImage: "target",
                        description: Text("Start or activate a search cycle before creating goals.")
                    )
                }
            }
            .navigationTitle("Goal Tracking")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Goal Action Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
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
            editingGoal = nil
            selectedMetric = .applicationsSubmitted
            selectedCadence = .weekly
            targetValue = ""
        } catch {
            errorMessage = error.localizedDescription
        }
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
