import SwiftUI
import SwiftData
import Charts
import PipelineKit

struct DashboardView: View {
    @Query private var applications: [JobApplication]
    @State private var viewModel = DashboardViewModel()
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary Cards
                summaryCards

                // Funnel Chart
                if !viewModel.funnel.isEmpty {
                    funnelChart
                }

                // Weekly Activity
                if !viewModel.weeklyActivity.isEmpty {
                    weeklyActivityChart
                }

                // Time in Stage
                if !viewModel.timeInStage.isEmpty {
                    timeInStageChart
                }

                // Response Rates
                ratesSection
            }
            .padding(20)
        }
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .onAppear { viewModel.refresh(applications: applications) }
        .onChange(of: applications.count) { _, _ in
            viewModel.refresh(applications: applications)
        }
    }

    // MARK: - Summary Cards

    private var summaryCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            summaryCard(title: "Total", value: "\(viewModel.totalApplications)", icon: "doc.text.fill", color: .blue)
            summaryCard(title: "Active", value: "\(viewModel.activeApplications)", icon: "flame.fill", color: .orange)
            summaryCard(title: "Response Rate", value: percentString(viewModel.responseRate), icon: "envelope.open.fill", color: .green)
            summaryCard(title: "Offer Rate", value: percentString(viewModel.offerRate), icon: "gift.fill", color: .purple)
        }
    }

    private func summaryCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.system(size: 14))
                Spacer()
            }
            HStack {
                Text(value)
                    .font(.title)
                    .fontWeight(.bold)
                Spacer()
            }
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(14)
        .appCard(cornerRadius: 12, elevated: true, shadow: false)
    }

    // MARK: - Funnel Chart

    private var funnelChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .foregroundColor(.blue)
                Text("Application Funnel")
                    .font(.headline)
            }

            Chart(viewModel.funnel) { item in
                BarMark(
                    x: .value("Status", item.status.displayName),
                    y: .value("Count", item.count)
                )
                .foregroundStyle(item.status.color)
                .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    if let intValue = value.as(Int.self) {
                        AxisValueLabel { Text("\(intValue)") }
                        AxisGridLine()
                    }
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    // MARK: - Weekly Activity

    private var weeklyActivityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(.green)
                Text("Weekly Activity")
                    .font(.headline)
                Text("Last 8 weeks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Chart(viewModel.weeklyActivity) { item in
                LineMark(
                    x: .value("Week", item.weekStart, unit: .weekOfYear),
                    y: .value("Applications", item.count)
                )
                .foregroundStyle(DesignSystem.Colors.accent)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Week", item.weekStart, unit: .weekOfYear),
                    y: .value("Applications", item.count)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [DesignSystem.Colors.accent.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Week", item.weekStart, unit: .weekOfYear),
                    y: .value("Applications", item.count)
                )
                .foregroundStyle(DesignSystem.Colors.accent)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.month(.abbreviated).day())
                                .font(.caption2)
                        }
                    }
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    // MARK: - Time in Stage

    private var timeInStageChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                Text("Average Time in Stage")
                    .font(.headline)
            }

            Chart(viewModel.timeInStage) { item in
                BarMark(
                    x: .value("Days", item.averageDays),
                    y: .value("Stage", item.status.displayName)
                )
                .foregroundStyle(item.status.color)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading) {
                    Text("\(Int(item.averageDays))d")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .chartXAxisLabel("Days")
            .frame(height: CGFloat(viewModel.timeInStage.count) * 50 + 20)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    // MARK: - Rates

    private var ratesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "percent")
                    .foregroundColor(.purple)
                Text("Conversion Rates")
                    .font(.headline)
            }

            HStack(spacing: 16) {
                rateGauge(label: "Response", value: viewModel.responseRate, color: .green)
                rateGauge(label: "Interview", value: viewModel.interviewRate, color: .orange)
                rateGauge(label: "Offer", value: viewModel.offerRate, color: .purple)
            }
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func rateGauge(label: String, value: Double, color: Color) -> some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.2), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: value)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text(percentString(value))
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(width: 70, height: 70)

            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func percentString(_ value: Double) -> String {
        "\(Int(value * 100))%"
    }
}

#Preview {
    DashboardView()
        .modelContainer(for: [JobApplication.self, InterviewLog.self], inMemory: true)
}
