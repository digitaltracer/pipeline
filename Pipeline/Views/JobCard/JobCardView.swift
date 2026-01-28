import SwiftUI

struct JobCardView: View {
    let application: JobApplication
    var isSelected: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Priority
            HStack(alignment: .top) {
                CompanyAvatar(
                    companyName: application.companyName,
                    logoURL: application.companyLogoURL ?? logoURL,
                    size: 44
                )

                Spacer()

                PriorityFlag(priority: application.priority, size: 16)
            }

            // Role & Company
            VStack(alignment: .leading, spacing: 4) {
                Text(application.role)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(application.companyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Location & Platform
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.caption)
                    Text(application.location)
                        .font(.caption)
                }
                .foregroundColor(.secondary)
                .lineLimit(1)

                Spacer()

                PlatformIcon(platform: application.platform, size: 14)
            }

            Divider()

            // Status & Salary
            HStack {
                StatusBadge(status: application.status, size: .small)

                Spacer()

                if let salaryRange = application.salaryRange {
                    Text(salaryRange)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Interview Stage (if interviewing)
            if application.status == .interviewing, let stage = application.interviewStage {
                HStack(spacing: 4) {
                    Image(systemName: stage.icon)
                        .font(.caption)
                        .foregroundColor(stage.color)

                    Text(stage.displayName)
                        .font(.caption)
                        .foregroundColor(stage.color)
                }
            }

            // Follow-up Date
            if let followUpDate = application.nextFollowUpDate {
                HStack(spacing: 4) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.caption)

                    Text("Follow-up: \(followUpDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                }
                .foregroundColor(followUpDate < Date() ? .red : .orange)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.textBackgroundColor))
                .shadow(color: isSelected ? .blue.opacity(0.3) : .black.opacity(0.1), radius: isSelected ? 8 : 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var logoURL: String? {
        guard let domain = application.companyDomain else { return nil }
        return "https://logo.clearbit.com/\(domain)"
    }
}

#Preview {
    VStack(spacing: 16) {
        JobCardView(
            application: JobApplication(
                companyName: "Apple",
                role: "Senior iOS Developer",
                location: "Cupertino, CA",
                status: .interviewing,
                priority: .high,
                platform: .linkedin,
                interviewStage: .technicalRound1,
                currency: .usd,
                salaryMin: 180000,
                salaryMax: 250000,
                nextFollowUpDate: Date().addingTimeInterval(86400 * 2)
            ),
            isSelected: true
        )

        JobCardView(
            application: JobApplication(
                companyName: "Google",
                role: "Staff Software Engineer",
                location: "Mountain View, CA",
                status: .applied,
                priority: .medium,
                platform: .linkedin,
                currency: .usd,
                salaryMin: 200000,
                salaryMax: 300000
            )
        )
    }
    .padding()
    .frame(width: 320)
}
