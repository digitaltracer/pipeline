import SwiftUI
import SwiftData
import Charts
import PipelineKit

struct CostCenterView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme

    @Query(sort: \JobApplication.updatedAt, order: .reverse) private var applications: [JobApplication]
    @Query(sort: \CompanyProfile.updatedAt, order: .reverse) private var companies: [CompanyProfile]
    @Query(sort: \AIUsageRecord.finishedAt, order: .reverse) private var usageRecords: [AIUsageRecord]
    @Query(sort: \AIModelRate.updatedAt, order: .reverse) private var modelRates: [AIModelRate]

    @State private var selectedWindow: TimeWindow = .thirtyDays
    @State private var addProvider: AIProvider = .openAI
    @State private var addModel: String = ""
    @State private var addInputRate: Double = 0
    @State private var addOutputRate: Double = 0
    @State private var actionError: String?

    private let recentRunsMaxHeight: CGFloat = 360

    private enum TimeWindow: String, CaseIterable, Identifiable {
        case sevenDays = "Last 7 days"
        case fourteenDays = "Last 14 days"
        case thirtyDays = "Last 30 days"
        case all = "All time"

        var id: String { rawValue }

        var title: String {
            rawValue
        }

        var cutoffDate: Date? {
            let calendar = Calendar.current
            switch self {
            case .sevenDays:
                return calendar.date(byAdding: .day, value: -7, to: Date())
            case .fourteenDays:
                return calendar.date(byAdding: .day, value: -14, to: Date())
            case .thirtyDays:
                return calendar.date(byAdding: .day, value: -30, to: Date())
            case .all:
                return nil
            }
        }
    }

    private struct BreakdownRow: Identifiable {
        let id: String
        let label: String
        let runs: Int
        let totalTokens: Int
        let totalCostUSD: Double
    }

    private var filteredRecords: [AIUsageRecord] {
        guard let cutoff = selectedWindow.cutoffDate else {
            return usageRecords
        }

        return usageRecords.filter { $0.finishedAt >= cutoff }
    }

    private var sortedRates: [AIModelRate] {
        modelRates.sorted {
            if $0.providerID == $1.providerID {
                return $0.model.localizedCaseInsensitiveCompare($1.model) == .orderedAscending
            }
            return $0.providerID.localizedCaseInsensitiveCompare($1.providerID) == .orderedAscending
        }
    }

    private var totalRuns: Int {
        filteredRecords.count
    }

    private var failedRuns: Int {
        filteredRecords.filter { $0.requestStatus == .failed }.count
    }

    private var totalTokens: Int {
        filteredRecords.reduce(0) { partialResult, record in
            partialResult + (record.totalTokens ?? 0)
        }
    }

    private var totalCostUSD: Double {
        filteredRecords.reduce(0) { partialResult, record in
            partialResult + (record.totalCostUSD ?? 0)
        }
    }

    private var providerBreakdown: [BreakdownRow] {
        var grouped: [String: (runs: Int, tokens: Int, cost: Double)] = [:]

        for record in filteredRecords {
            var entry = grouped[record.providerID, default: (runs: 0, tokens: 0, cost: 0)]
            entry.runs += 1
            entry.tokens += record.totalTokens ?? 0
            entry.cost += record.totalCostUSD ?? 0
            grouped[record.providerID] = entry
        }

        return grouped.map { key, value in
            BreakdownRow(
                id: key,
                label: providerDisplayName(for: key),
                runs: value.runs,
                totalTokens: value.tokens,
                totalCostUSD: value.cost
            )
        }
        .sorted { $0.totalCostUSD > $1.totalCostUSD }
    }

    private var modelBreakdown: [BreakdownRow] {
        var grouped: [String: (label: String, runs: Int, tokens: Int, cost: Double)] = [:]

        for record in filteredRecords {
            let key = "\(record.providerID)::\(record.model)"
            var entry = grouped[key, default: (label: record.model, runs: 0, tokens: 0, cost: 0)]
            entry.runs += 1
            entry.tokens += record.totalTokens ?? 0
            entry.cost += record.totalCostUSD ?? 0
            grouped[key] = entry
        }

        return grouped.map { key, value in
            BreakdownRow(
                id: key,
                label: value.label,
                runs: value.runs,
                totalTokens: value.tokens,
                totalCostUSD: value.cost
            )
        }
        .sorted { $0.totalCostUSD > $1.totalCostUSD }
    }

    private var featureBreakdown: [BreakdownRow] {
        var grouped: [String: (runs: Int, tokens: Int, cost: Double)] = [:]

        for record in filteredRecords {
            let key = record.feature.title
            var entry = grouped[key, default: (runs: 0, tokens: 0, cost: 0)]
            entry.runs += 1
            entry.tokens += record.totalTokens ?? 0
            entry.cost += record.totalCostUSD ?? 0
            grouped[key] = entry
        }

        return grouped.map { key, value in
            BreakdownRow(
                id: key,
                label: key,
                runs: value.runs,
                totalTokens: value.tokens,
                totalCostUSD: value.cost
            )
        }
        .sorted { $0.totalCostUSD > $1.totalCostUSD }
    }

    private var missingRateRecords: [AIUsageRecord] {
        filteredRecords.filter {
            $0.promptTokens != nil &&
            $0.completionTokens != nil &&
            $0.totalCostUSD == nil
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                windowSelector
                summaryCards
                spendPanels
                modelBreakdownCard
                recentRunsCard

                if !missingRateRecords.isEmpty {
                    missingRateWarning
                }

                rateEditorCard
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .onAppear {
            do {
                try AIUsageLedgerService.seedDefaultRatesIfNeeded(in: modelContext)
                _ = try AIUsageLedgerService.backfillMissingCostsIfNeeded(in: modelContext)
            } catch {
                actionError = error.localizedDescription
            }
        }
        .alert("Cost Center Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cost Center")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("AI usage ledger and dashboard")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Clear") {
                selectedWindow = .all
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var windowSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(TimeWindow.allCases) { window in
                    Button {
                        selectedWindow = window
                    } label: {
                        Text(window.rawValue)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selectedWindow == window ? DesignSystem.Colors.accent : DesignSystem.Colors.inputBackground(colorScheme))
                            )
                            .foregroundStyle(selectedWindow == window ? Color.white : Color.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var summaryCards: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                summaryCard(title: "Total Tokens", value: formatTokens(totalTokens), icon: "number", color: .blue)
                summaryCard(title: "Total Cost", value: formatUSD(totalCostUSD), icon: "dollarsign.circle.fill", color: .green)
                summaryCard(title: "API Calls", value: "\(totalRuns)", icon: "waveform.path.ecg", color: .orange)
            }

            VStack(spacing: 12) {
                summaryCard(title: "Total Tokens", value: formatTokens(totalTokens), icon: "number", color: .blue)
                summaryCard(title: "Total Cost", value: formatUSD(totalCostUSD), icon: "dollarsign.circle.fill", color: .green)
                summaryCard(title: "API Calls", value: "\(totalRuns)", icon: "waveform.path.ecg", color: .orange)
            }
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)

            Text(value)
                .font(.title3.weight(.semibold))

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private var spendPanels: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                spendByProviderCard
                spendByFeatureCard
            }
            VStack(spacing: 12) {
                spendByProviderCard
                spendByFeatureCard
            }
        }
    }

    private var spendByProviderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spend by Provider")
                .font(.headline)

            if providerBreakdown.isEmpty {
                Text("No provider usage in \(selectedWindow.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
            } else {
                Chart(providerBreakdown) { row in
                    BarMark(
                        x: .value("Provider", row.label),
                        y: .value("Spend", row.totalCostUSD),
                        width: .fixed(72)
                    )
                    .cornerRadius(6)
                    .foregroundStyle(by: .value("Provider", row.label))
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartForegroundStyleScale(
                    domain: providerBreakdown.map(\.label),
                    range: chartPalette(for: providerBreakdown.count)
                )
                .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private var spendByFeatureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spend by Feature")
                .font(.headline)

            if featureBreakdown.isEmpty {
                Text("No feature usage in \(selectedWindow.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .center)
            } else {
                Chart(featureBreakdown) { row in
                    SectorMark(
                        angle: .value("Spend", row.totalCostUSD),
                        innerRadius: .ratio(0.56),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Feature", row.label))
                }
                .chartForegroundStyleScale(
                    domain: featureBreakdown.map(\.label),
                    range: chartPalette(for: featureBreakdown.count)
                )
                .chartLegend(position: .bottom, alignment: .center, spacing: 8)
                .frame(height: 170)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private var modelBreakdownCard: some View {
        let rows = Array(modelBreakdown.prefix(8))

        return VStack(alignment: .leading, spacing: 10) {
            Text("Breakdown by Model")
                .font(.headline)

            HStack {
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("Calls").frame(width: 70, alignment: .trailing)
                Text("Tokens").frame(width: 90, alignment: .trailing)
                Text("Cost (USD)").frame(width: 110, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            if rows.isEmpty {
                Text("No model usage in \(selectedWindow.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(rows) { row in
                    HStack {
                        Text(row.label)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.runs)")
                            .font(.caption)
                            .frame(width: 70, alignment: .trailing)
                        Text(formatTokens(row.totalTokens))
                            .font(.caption)
                            .frame(width: 90, alignment: .trailing)
                        Text(formatUSD(row.totalCostUSD))
                            .font(.caption)
                            .frame(width: 110, alignment: .trailing)
                    }
                    Divider().overlay(DesignSystem.Colors.divider(colorScheme))
                }
            }
        }
        .padding(14)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private var missingRateWarning: some View {
        let modelKeys = Set(missingRateRecords.map { "\($0.providerID)/\($0.model)" })

        return VStack(alignment: .leading, spacing: 8) {
            Label("Missing pricing for \(modelKeys.count) model(s)", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("These runs have token usage but no matching rate, so cost is unavailable until you add rates.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(Array(modelKeys).sorted(), id: \.self) { key in
                Text("• \(key)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .appCard(cornerRadius: 12, elevated: true, shadow: false)
    }

    private var rateEditorCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Provider Cost Table (USD per 1M tokens)")
                    .font(.headline)

                Spacer()

                Button("Reset Defaults") {
                    do {
                        try AIUsageLedgerService.resetRatesToDefaults(in: modelContext)
                    } catch {
                        actionError = error.localizedDescription
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Picker("Provider", selection: $addProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .frame(width: 180)

                TextField("Model", text: $addModel)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 180)

                TextField("Input", value: $addInputRate, format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                TextField("Output", value: $addOutputRate, format: .number.precision(.fractionLength(4)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)

                Button("Add / Update") {
                    saveRateFromForm()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(addModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if sortedRates.isEmpty {
                Text("No model rates available yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Text("Provider").frame(width: 120, alignment: .leading)
                        Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Input").frame(width: 110, alignment: .leading)
                        Text("Output").frame(width: 110, alignment: .leading)
                        Text("").frame(width: 34, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                    ForEach(sortedRates) { rate in
                        HStack(spacing: 10) {
                            Text(providerDisplayName(for: rate.providerID))
                                .font(.caption)
                                .frame(width: 120, alignment: .leading)
                            Text(rate.model)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            TextField(
                                "Input",
                                value: binding(for: rate, keyPath: \.inputUSDPerMillion),
                                format: .number.precision(.fractionLength(4))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)

                            TextField(
                                "Output",
                                value: binding(for: rate, keyPath: \.outputUSDPerMillion),
                                format: .number.precision(.fractionLength(4))
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)

                            Button {
                                deleteRate(rate)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                            .frame(width: 34, alignment: .trailing)
                            .fastTooltip("Remove this provider/model cost rate")
                        }
                    }
                }
            }
        }
        .padding(14)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private var recentRunsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Usage Log")
                .font(.headline)

            HStack {
                Text("Time").frame(width: 140, alignment: .leading)
                Text("Provider").frame(width: 90, alignment: .leading)
                Text("Model").frame(maxWidth: .infinity, alignment: .leading)
                Text("Feature").frame(width: 120, alignment: .leading)
                Text("Context").frame(width: 180, alignment: .leading)
                Text("Tokens").frame(width: 90, alignment: .trailing)
                Text("Cost").frame(width: 95, alignment: .trailing)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            Divider().overlay(DesignSystem.Colors.divider(colorScheme))

            if filteredRecords.isEmpty {
                Text("No usage records yet for \(selectedWindow.title).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(filteredRecords.prefix(20))) { record in
                            HStack {
                                Text(formatDateTime(record.finishedAt))
                                    .font(.caption2)
                                    .frame(width: 140, alignment: .leading)

                                Text(providerDisplayName(for: record.providerID))
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 90, alignment: .leading)

                                Text(record.model)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(record.feature.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .frame(width: 120, alignment: .leading)

                                Text(contextLabel(for: record))
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: 180, alignment: .leading)

                                Text(formatTokens(record.totalTokens ?? 0))
                                    .font(.caption)
                                    .frame(width: 90, alignment: .trailing)

                                Text(record.totalCostUSD.map(formatUSD) ?? "N/A")
                                    .font(.caption)
                                    .frame(width: 95, alignment: .trailing)
                            }
                            .padding(.vertical, 6)

                            Divider().overlay(DesignSystem.Colors.divider(colorScheme))
                        }
                    }
                }
                .frame(maxHeight: recentRunsMaxHeight)
            }
        }
        .padding(14)
        .appCard(cornerRadius: 10, elevated: true, shadow: false)
    }

    private func binding(
        for rate: AIModelRate,
        keyPath: ReferenceWritableKeyPath<AIModelRate, Double>
    ) -> Binding<Double> {
        Binding(
            get: { rate[keyPath: keyPath] },
            set: { newValue in
                rate[keyPath: keyPath] = max(0, newValue)
                rate.source = .user
                rate.updatedAt = Date()
                try? modelContext.save()
            }
        )
    }

    private func saveRateFromForm() {
        do {
            try AIUsageLedgerService.upsertRate(
                providerID: addProvider.providerID,
                model: addModel,
                inputUSDPerMillion: addInputRate,
                outputUSDPerMillion: addOutputRate,
                source: .user,
                in: modelContext
            )
            addModel = ""
            addInputRate = 0
            addOutputRate = 0
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deleteRate(_ rate: AIModelRate) {
        do {
            modelContext.delete(rate)
            try modelContext.save()
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func chartPalette(for count: Int) -> [Color] {
        let base: [Color] = [.blue, .green, .orange, .teal, .indigo, .mint]
        guard count > base.count else {
            return Array(base.prefix(max(count, 1)))
        }

        return Array(repeating: base, count: (count / base.count) + 1).flatMap { $0 }.prefix(count).map { $0 }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy hh:mm a"
        return formatter.string(from: date)
    }

    private func providerDisplayName(for providerID: String) -> String {
        if let descriptor = AIProviderRegistry.allDescriptors.first(where: {
            $0.providerID.caseInsensitiveCompare(providerID) == .orderedSame
        }) {
            return descriptor.provider.rawValue
        }

        return providerID.capitalized
    }

    private func formatUSD(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }

    private func formatTokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }

    private func contextLabel(for record: AIUsageRecord) -> String {
        if let companyID = record.companyID,
           let company = companies.first(where: { $0.id == companyID }) {
            return company.name
        }

        if let applicationID = record.applicationID,
           let application = applications.first(where: { $0.id == applicationID }) {
            return "\(application.companyName) · \(application.role)"
        }

        return "—"
    }
}

#Preview {
    CostCenterView()
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
                ATSCompatibilityScanRun.self,
                ResumeMasterRevision.self,
                ResumeJobSnapshot.self,
                AIUsageRecord.self,
                AIModelRate.self
            ],
            inMemory: true
        )
}
