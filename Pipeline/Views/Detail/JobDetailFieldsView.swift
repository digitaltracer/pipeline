import SwiftUI
import PipelineKit

struct JobDetailFieldsView: View {
    let application: JobApplication

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            DetailInfoCard(
                label: "Location",
                value: application.location,
                icon: "mappin.circle.fill",
                iconColor: .red
            )

            DetailInfoCard(
                label: "Source",
                value: application.source.displayName,
                icon: application.source.icon,
                iconColor: application.source.color
            )

            DetailInfoCard(
                label: "Platform",
                value: application.platform.displayName,
                icon: application.platform.icon,
                iconColor: application.platform.color
            )

            DetailInfoCard(
                label: "Search Cycle",
                value: application.cycle?.name ?? "—",
                icon: "scope",
                iconColor: .blue
            )

            if let salaryRange = application.salaryRange {
                DetailInfoCard(
                    label: "Posted Base",
                    value: salaryRange,
                    icon: "dollarsign.circle",
                    iconColor: .green
                )
            } else {
                DetailInfoCard(
                    label: "Posted Base",
                    value: "—",
                    icon: "dollarsign.circle",
                    iconColor: .green
                )
            }

            DetailInfoCard(
                label: "Posted Total Comp",
                value: application.postedTotalCompRange ?? "—",
                icon: "chart.bar.fill",
                iconColor: .green
            )

            DetailInfoCard(
                label: "Expected Total Comp",
                value: application.expectedTotalCompRange ?? "—",
                icon: "flag.fill",
                iconColor: .orange
            )

            DetailInfoCard(
                label: "Offer Total Comp (Year 1)",
                value: application.offerYearOneTotalCompText ?? "—",
                icon: "gift.fill",
                iconColor: .purple
            )

            DetailInfoCard(
                label: "Equity (4yr est.)",
                value: application.offerEquityCompensation.map(application.currency.format) ?? "—",
                icon: "chart.line.uptrend.xyaxis",
                iconColor: .purple
            )

            DetailInfoCard(
                label: "PTO",
                value: application.offerPTOText ?? "—",
                icon: "figure.walk",
                iconColor: .mint
            )

            DetailInfoCard(
                label: "Remote Policy",
                value: application.offerRemotePolicyText ?? "—",
                icon: "house",
                iconColor: .blue
            )

            DetailInfoCard(
                label: "Growth Score",
                value: starText(for: application.offerGrowthScore),
                icon: "arrow.up.right.circle.fill",
                iconColor: .orange
            )

            DetailInfoCard(
                label: "Team/Culture Fit",
                value: starText(for: application.offerTeamCultureFitScore),
                icon: "person.3.fill",
                iconColor: .pink
            )

            if let appliedDate = application.appliedDate {
                DetailInfoCard(
                    label: "Applied On",
                    value: appliedDate.formatted(date: .long, time: .omitted),
                    icon: "calendar",
                    iconColor: .blue
                )
            }

            if let followUpDate = application.nextFollowUpDate {
                DetailInfoCard(
                    label: "Next Follow Up",
                    value: followUpDate.formatted(date: .long, time: .omitted),
                    icon: "calendar.badge.clock",
                    iconColor: followUpDate < Date() ? .red : .orange
                )
            }

            if let postedAt = application.postedAt {
                DetailInfoCard(
                    label: "Posted On",
                    value: postedAt.formatted(date: .long, time: .omitted),
                    icon: "calendar.badge.plus",
                    iconColor: .teal
                )
            }

            if let applicationDeadline = application.applicationDeadline {
                DetailInfoCard(
                    label: "Apply By",
                    value: applicationDeadline.formatted(date: .long, time: .omitted),
                    icon: "hourglass",
                    iconColor: applicationDeadline < Date() ? .red : .orange
                )
            }

            DetailInfoCard(
                label: "Apply Queue",
                value: application.isQueuedForApplyLater ? "Queued" : "Not queued",
                icon: application.isQueuedForApplyLater ? "bookmark.fill" : "bookmark",
                iconColor: application.isQueuedForApplyLater ? .blue : .secondary
            )
        }
    }

    private func starText(for score: Int?) -> String {
        guard let score, score > 0 else { return "—" }
        return String(repeating: "★", count: score)
    }
}

struct DetailInfoCard: View {
    let label: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                    .frame(width: 18)

                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(value == "—" ? .secondary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

#Preview {
    JobDetailFieldsView(
        application: JobApplication(
            companyName: "Apple",
            role: "Senior iOS Developer",
            location: "Cupertino, CA",
            status: .interviewing,
            priority: .high,
            source: .companyWebsite,
            platform: .linkedin,
            currency: .usd,
            salaryMin: 180000,
            salaryMax: 250000,
            appliedDate: Date().addingTimeInterval(-86400 * 14),
            nextFollowUpDate: Date().addingTimeInterval(86400 * 2)
        )
    )
    .padding()
}
