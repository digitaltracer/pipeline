import SwiftUI
import PipelineKit

struct JobCardView: View {
    let application: JobApplication
    var isSelected: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var salaryText: String {
        application.salaryRange ?? "—"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header: Avatar + Role/Company + Priority Flag
            HStack(alignment: .top, spacing: 12) {
                CompanyAvatar(
                    companyName: application.companyName,
                    logoURL: application.googleS2FaviconURL(size: 64)?.absoluteString,
                    size: 44,
                    cornerRadius: 14
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(application.role)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)

                    Text(application.companyName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                PriorityFlag(priority: application.priority, showLabel: false, size: 14)
            }

            // Location & Platform
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(application.location)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .lineLimit(1)

                Spacer()

                PlatformDotLabel(platform: application.platform, fontSize: 12)
            }

            // Status & Salary
            HStack(spacing: 10) {
                StatusBadge(status: application.status, size: .small)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Text(salaryText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .opacity(application.salaryRange == nil ? 0.75 : 1)
            }

            // Stage/Offer Tag & Follow-up Date
            HStack {
                if application.status == .interviewing, let stage = application.interviewStage {
                    TagBadge(text: stage.displayName, color: stage.color, size: .small)
                } else if application.status == .offered {
                    TagBadge(text: "Offer Extended", color: .orange, icon: "gift.fill", size: .small)
                } else {
                    TagBadge(text: "—", color: .secondary, size: .small)
                        .opacity(0.75)
                }

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11))
                    Text(application.nextFollowUpDate?.formatted(date: .abbreviated, time: .omitted) ?? "—")
                        .font(.caption)
                }
                .foregroundColor(application.nextFollowUpDate.map { $0 < Date() } == true ? .red : .secondary)
                .opacity(application.nextFollowUpDate == nil ? 0.75 : 1)
            }
        }
        .padding()
        .appCard(cornerRadius: 14, elevated: true, shadow: true)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.stroke(colorScheme), lineWidth: isSelected ? 2 : 1)
                .opacity(isSelected ? 1 : 0.6)
        )
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
                interviewStage: .technicalRound2,
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
                platform: .indeed,
                currency: .usd,
                salaryMin: 200000,
                salaryMax: 300000
            )
        )
    }
    .padding()
    .frame(width: 320)
}
