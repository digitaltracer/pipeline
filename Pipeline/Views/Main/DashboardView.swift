import SwiftUI
import SwiftData
import Charts
import PipelineKit

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \JobSearchCycle.updatedAt, order: .reverse) private var cycles: [JobSearchCycle]
    @Query(sort: \SearchGoal.updatedAt, order: .reverse) private var goals: [SearchGoal]
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
        return "\(viewModel.selectedScope.rawValue)|\(settingsViewModel.analyticsBaseCurrency.rawValue)|\(appToken)|\(cycleToken)|\(goalToken)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let analytics = viewModel.analytics {
                    if viewModel.summaryCards.isEmpty {
                        emptyStateCard
                    } else {
                        summaryCards
                        goalTrackingSection(analytics: analytics)
                        cadenceHeatmapSection(analytics: analytics)
                        salarySection(analytics: analytics)
                        funnelSection(analytics: analytics)
                        timeInStageSection(analytics: analytics)
                        ratesSection(analytics: analytics)
                    }
                } else if viewModel.isRefreshing {
                    loadingCard
                } else {
                    emptyStateCard
                }
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .task(id: refreshToken) {
            await viewModel.refresh(
                applications: applications,
                cycles: cycles,
                goals: goals,
                baseCurrency: settingsViewModel.analyticsBaseCurrency
            )
        }
        .sheet(isPresented: $showingCycleManager) {
            CycleManagementSheet()
        }
        .sheet(isPresented: $showingGoalManager) {
            GoalManagementSheet(activeCycle: viewModel.analytics?.activeCycle)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Dashboard")
                        .font(.largeTitle.weight(.bold))

                    Text(viewModel.analytics?.comparisonLabel ?? "Track search momentum, cycle progress, and compensation signals.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 10) {
                    Picker("Scope", selection: $viewModel.selectedScope) {
                        ForEach(AnalyticsComparisonScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)

                    Button("Cycles") {
                        showingCycleManager = true
                    }
                    .buttonStyle(.bordered)

                    Button("Goals") {
                        showingGoalManager = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                }
            }

            HStack(spacing: 12) {
                dashboardBadge(
                    icon: "arrow.left.arrow.right.circle.fill",
                    title: "Base Currency",
                    value: settingsViewModel.analyticsBaseCurrency.rawValue
                )

                dashboardBadge(
                    icon: "viewfinder.circle",
                    title: "Active Cycle",
                    value: viewModel.analytics?.activeCycle?.name ?? "None"
                )

                if let analytics = viewModel.analytics, analytics.fxUsedFallback || analytics.missingSalaryConversionCount > 0 {
                    dashboardBadge(
                        icon: "arrow.clockwise",
                        title: "FX Status",
                        value: analytics.fxUsedFallback ? "Using cached rates" : "\(analytics.missingSalaryConversionCount) missing conversions"
                    )
                }
            }
        }
    }

    private func dashboardBadge(icon: String, title: String, value: String) -> some View {
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

    private var summaryCards: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            ForEach(viewModel.summaryCards) { card in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: card.icon)
                            .foregroundColor(DesignSystem.Colors.accent)
                        Spacer()
                        Text(card.deltaText)
                            .font(.caption.weight(.semibold))
                            .foregroundColor(deltaColor(named: card.deltaColorName))
                    }

                    Text(card.value)
                        .font(.system(size: 28, weight: .bold, design: .rounded))

                    Text(card.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)
            }
        }
    }

    private func goalTrackingSection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Goal Tracking", systemImage: "target")
                    .font(.headline)

                Spacer()

                if let activeCycle = analytics.activeCycle {
                    Text(activeCycle.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if analytics.goalProgress.isEmpty {
                ContentUnavailableView(
                    "No goals yet",
                    systemImage: "target",
                    description: Text("Create weekly or monthly goals for the active search cycle.")
                )
            } else {
                ForEach(analytics.goalProgress) { progress in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(progress.title, systemImage: progress.metric.icon)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(progress.progress) / \(progress.target)")
                                .font(.subheadline.weight(.semibold))
                        }

                        ProgressView(value: min(Double(progress.progress), Double(progress.target)), total: Double(progress.target))
                            .tint(DesignSystem.Colors.accent)

                        Text(progress.periodLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                    )
                }
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func cadenceHeatmapSection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Application Cadence", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                Text("Last 12 weeks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if analytics.cadenceHeatmap.isEmpty {
                Text("No submitted applications in this scope yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                CadenceHeatmapView(cells: analytics.cadenceHeatmap)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func salarySection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Salary Analytics", systemImage: "banknote")
                    .font(.headline)
                Spacer()
                Text("Base currency: \(settingsViewModel.analyticsBaseCurrency.rawValue)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if analytics.salaryDistribution.isEmpty && analytics.averageExpectedComp == nil && analytics.averageOfferedComp == nil {
                ContentUnavailableView(
                    "No compensation analytics yet",
                    systemImage: "chart.bar.xaxis",
                    description: Text("Add posted, expected, or offer compensation to applications in this scope.")
                )
            } else {
                if !analytics.salaryDistribution.isEmpty {
                    Chart(analytics.salaryDistribution) { bin in
                        BarMark(
                            x: .value("Range", bin.label),
                            y: .value("Applications", bin.count)
                        )
                        .foregroundStyle(DesignSystem.Colors.accent)
                        .cornerRadius(4)
                    }
                    .frame(height: 220)
                }

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
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
        )
    }

    private func funnelSection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Application Funnel", systemImage: "chart.bar.fill")
                .font(.headline)

            Chart(analytics.funnel) { item in
                BarMark(
                    x: .value("Status", item.status.displayName),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(item.status.color)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 220)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func timeInStageSection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Average Time in Stage", systemImage: "clock.fill")
                .font(.headline)

            if analytics.timeInStage.isEmpty {
                Text("Not enough in-scope data for stage timing yet.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Chart(analytics.timeInStage) { item in
                    BarMark(
                        x: .value("Days", item.averageDays),
                        y: .value("Stage", item.status.displayName)
                    )
                    .foregroundStyle(item.status.color)
                    .cornerRadius(4)
                    .annotation(position: .trailing) {
                        Text("\(Int(item.averageDays.rounded()))d")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(height: CGFloat(analytics.timeInStage.count) * 52 + 12)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func ratesSection(analytics: DashboardAnalyticsResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Conversion Rates", systemImage: "percent")
                .font(.headline)

            HStack(spacing: 16) {
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
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func rateGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.18), lineWidth: 8)

                Circle()
                    .trim(from: 0, to: max(0, min(value, 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(viewModel.percentString(value))
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(width: 76, height: 76)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var loadingCard: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Refreshing analytics…")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private var emptyStateCard: some View {
        ContentUnavailableView(
            "No analytics yet",
            systemImage: "chart.xyaxis.line",
            description: Text("Add a few applications or create a search cycle to populate the dashboard.")
        )
        .frame(maxWidth: .infinity)
        .padding(32)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
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
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(0..<7, id: \.self) { index in
                    Text(weekdayLabels[index])
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(height: 18)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 6) {
                    ForEach(grouped, id: \.week) { column in
                        VStack(spacing: 6) {
                            ForEach(column.cells) { cell in
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(heatColor(for: cell.count))
                                    .frame(width: 18, height: 18)
                                    .overlay {
                                        if cell.count > 0 {
                                            Text("\(cell.count)")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(.white)
                                        }
                                    }
                            }

                            Text(column.week, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .rotationEffect(.degrees(-45))
                                .frame(width: 36, height: 28, alignment: .topLeading)
                        }
                    }
                }
            }
        }
    }

    private func heatColor(for count: Int) -> Color {
        switch count {
        case 0:
            return Color.secondary.opacity(0.12)
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
                Contact.self,
                ApplicationContactLink.self,
                ApplicationActivity.self,
                ApplicationAttachment.self
            ],
            inMemory: true
        )
}
