import SwiftUI
import PipelineKit

struct StatsBarView: View {
    let stats: ApplicationStats
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 0) {
            StatItem(
                title: "Response Rate",
                value: stats.formattedResponseRate,
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )

            StatDivider()

            StatItem(
                title: "Applied",
                value: "\(stats.applied)",
                icon: "paperplane",
                color: .blue
            )

            StatDivider()

            StatItem(
                title: "Interviewing",
                value: "\(stats.interviewing)",
                icon: "message",
                color: .orange
            )

            StatDivider()

            StatItem(
                title: "Offers",
                value: "\(stats.offers)",
                icon: "gift",
                color: .green
            )

            StatDivider()

            StatItem(
                title: "Rejected",
                value: "\(stats.rejected)",
                icon: "xmark.circle",
                color: .red
            )
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
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
