import SwiftUI

struct JobDetailHeaderView: View {
    let application: JobApplication
    let onStatusChange: (ApplicationStatus) -> Void
    let onPriorityChange: (Priority) -> Void

    private var logoURL: String? {
        guard let domain = application.companyDomain else { return nil }
        return "https://logo.clearbit.com/\(domain)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            CompanyAvatar(
                companyName: application.companyName,
                logoURL: application.companyLogoURL ?? logoURL,
                size: 64
            )

            VStack(alignment: .leading, spacing: 8) {
                Text(application.role)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(application.companyName)
                    .font(.title3)
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    // Status Menu
                    Menu {
                        ForEach(ApplicationStatus.allCases) { status in
                            Button {
                                onStatusChange(status)
                            } label: {
                                Label(status.displayName, systemImage: status.icon)
                            }
                        }
                    } label: {
                        StatusBadge(status: application.status, showIcon: true)
                    }

                    // Priority Menu
                    Menu {
                        ForEach(Priority.allCases) { priority in
                            Button {
                                onPriorityChange(priority)
                            } label: {
                                Label(priority.displayName, systemImage: priority.icon)
                            }
                        }
                    } label: {
                        PriorityFlag(priority: application.priority, showLabel: true)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(application.priority.color.opacity(0.1))
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
    }
}

#Preview {
    JobDetailHeaderView(
        application: JobApplication(
            companyName: "Apple",
            role: "Senior iOS Developer",
            location: "Cupertino, CA",
            status: .interviewing,
            priority: .high
        ),
        onStatusChange: { _ in },
        onPriorityChange: { _ in }
    )
    .padding()
}
