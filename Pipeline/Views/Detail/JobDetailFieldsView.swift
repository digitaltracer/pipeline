import SwiftUI

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

            if let salaryRange = application.salaryRange {
                DetailInfoCard(
                    label: "Salary Package",
                    value: salaryRange,
                    icon: "dollarsign.circle",
                    iconColor: .green
                )
            } else {
                DetailInfoCard(
                    label: "Salary Package",
                    value: "—",
                    icon: "dollarsign.circle",
                    iconColor: .green
                )
            }

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
        }
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
