import SwiftUI

struct StatsBarView: View {
    let stats: ApplicationStats

    var body: some View {
        HStack(spacing: 0) {
            StatItem(
                title: "Response Rate",
                value: stats.formattedResponseRate,
                icon: "chart.line.uptrend.xyaxis",
                color: .blue
            )

            Divider()
                .frame(height: 40)

            StatItem(
                title: "Applied",
                value: "\(stats.applied)",
                icon: "paperplane.fill",
                color: .blue
            )

            Divider()
                .frame(height: 40)

            StatItem(
                title: "Interviewing",
                value: "\(stats.interviewing)",
                icon: "person.2.fill",
                color: .orange
            )

            Divider()
                .frame(height: 40)

            StatItem(
                title: "Offers",
                value: "\(stats.offers)",
                icon: "gift.fill",
                color: .green
            )

            Divider()
                .frame(height: 40)

            StatItem(
                title: "Rejected",
                value: "\(stats.rejected)",
                icon: "xmark.circle.fill",
                color: .red
            )
        }
        .padding(.vertical, 8)
        .background(Color(.textBackgroundColor).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct StatItem: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
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
    .frame(width: 600)
}
