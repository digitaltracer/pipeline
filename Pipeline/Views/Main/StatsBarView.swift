import SwiftUI
import PipelineKit

struct StatsBarView: View {
    let stats: ApplicationStats
    var isDetailPanelOpen: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    private var allItems: [StatMetric] {
        [
            StatMetric(id: "response-rate", title: "Response Rate", value: stats.formattedResponseRate, icon: "chart.line.uptrend.xyaxis", color: .blue),
            StatMetric(id: "applied", title: "Applied", value: "\(stats.applied)", icon: "paperplane", color: .blue),
            StatMetric(id: "interviewing", title: "Interviewing", value: "\(stats.interviewing)", icon: "message", color: .orange),
            StatMetric(id: "offers", title: "Offers", value: "\(stats.offers)", icon: "gift", color: .green),
            StatMetric(id: "rejected", title: "Rejected", value: "\(stats.rejected)", icon: "xmark.circle", color: .red)
        ]
    }

    var body: some View {
        Group {
            if isDetailPanelOpen {
                ViewThatFits(in: .horizontal) {
                    statsRow(showRejected: true)
                    statsRow(showRejected: false)
                }
            } else {
                statsRow(showRejected: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    private func statsRow(showRejected: Bool) -> some View {
        let items = showRejected ? allItems : allItems.filter { $0.id != "rejected" }

        return HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { index in
                let item = items[index]
                StatItem(
                    title: item.title,
                    value: item.value,
                    icon: item.icon,
                    color: item.color
                )

                if index < items.count - 1 {
                    StatDivider()
                }
            }
        }
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(color)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(minWidth: StatsBarLayout.minimumItemWidth, maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatMetric: Identifiable {
    let id: String
    let title: String
    let value: String
    let icon: String
    let color: Color
}

private enum StatsBarLayout {
    static let minimumItemWidth: CGFloat = 120
}

struct StatDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(DesignSystem.Colors.divider(colorScheme))
            .frame(width: 1)
            .padding(.vertical, 6)
            .opacity(0.6)
    }
}

#Preview {
    StatsBarView(stats: ApplicationStats(
        total: 25,
        applied: 15,
        interviewing: 4,
        offers: 2,
        rejected: 5,
        responseRate: 73.3
    ))
    .padding()
    .frame(width: 700)
}
