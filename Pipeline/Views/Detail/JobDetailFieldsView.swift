import SwiftUI

struct JobDetailFieldsView: View {
    let application: JobApplication

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
            DetailFieldItem(
                label: "Location",
                value: application.location,
                icon: "mappin.circle.fill",
                iconColor: .red
            )

            DetailFieldItem(
                label: "Source",
                value: application.source.displayName,
                icon: application.source.icon,
                iconColor: application.source.color
            )

            DetailFieldItem(
                label: "Platform",
                value: application.platform.displayName,
                icon: application.platform.icon,
                iconColor: application.platform.color
            )

            if let salaryRange = application.salaryRange {
                DetailFieldItem(
                    label: "Salary",
                    value: salaryRange,
                    icon: "banknote",
                    iconColor: .green
                )
            }

            if let appliedDate = application.appliedDate {
                DetailFieldItem(
                    label: "Applied",
                    value: appliedDate.formatted(date: .abbreviated, time: .omitted),
                    icon: "calendar",
                    iconColor: .blue
                )
            }

            if let followUpDate = application.nextFollowUpDate {
                DetailFieldItem(
                    label: "Follow-up",
                    value: followUpDate.formatted(date: .abbreviated, time: .omitted),
                    icon: "calendar.badge.clock",
                    iconColor: followUpDate < Date() ? .red : .orange
                )
            }

            DetailFieldItem(
                label: "Created",
                value: application.createdAt.formatted(date: .abbreviated, time: .omitted),
                icon: "clock",
                iconColor: .secondary
            )

            DetailFieldItem(
                label: "Updated",
                value: application.updatedAt.formatted(date: .abbreviated, time: .omitted),
                icon: "clock.arrow.circlepath",
                iconColor: .secondary
            )
        }
    }
}

struct DetailFieldItem: View {
    let label: String
    let value: String
    let icon: String
    let iconColor: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
            }
        }
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
