import SwiftUI
import PipelineKit

struct JobDetailField: Identifiable {
    let label: String
    let value: String
    let valueColor: Color?

    var id: String { label }
}

private struct JobDetailSection: Identifiable {
    let title: String
    let rows: [JobDetailField]

    var id: String { title }
}

struct JobDetailFieldsView: View {
    let application: JobApplication
    @State private var showsMoreDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            JobDetailTableCard(
                title: "Application Snapshot",
                sections: primarySections
            )

            if !secondarySections.isEmpty {
                DisclosureGroup(isExpanded: $showsMoreDetails) {
                    JobDetailTableContent(sections: secondarySections)
                        .padding(.top, 14)
                } label: {
                    HStack {
                        Text("More Details")
                            .font(.system(size: 13, weight: .semibold))

                        Spacer()

                        Text("\(secondaryRowCount) field\(secondaryRowCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tint(.primary)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .appCard(elevated: true)
            }
        }
    }

    private var primarySections: [JobDetailSection] {
        [
            JobDetailSection(
                title: "Overview",
                rows: [
                    JobDetailField(label: "Location", value: displayText(application.location), valueColor: nil),
                    JobDetailField(label: "Source", value: application.source.displayName, valueColor: nil),
                    JobDetailField(label: "Platform", value: application.platform.displayName, valueColor: nil)
                ]
            ),
            JobDetailSection(
                title: "Timeline",
                rows: [
                    JobDetailField(
                        label: "Next Follow Up",
                        value: formattedDate(application.nextFollowUpDate),
                        valueColor: application.nextFollowUpDate.map { $0 < Date() ? .red : .orange }
                    ),
                    JobDetailField(
                        label: "Apply By",
                        value: formattedDate(application.applicationDeadline),
                        valueColor: application.applicationDeadline.map { $0 < Date() ? .red : .orange }
                    )
                ]
            )
        ]
    }

    private var secondarySections: [JobDetailSection] {
        let compensationRows: [JobDetailField] = [
            JobDetailField(label: "Posted Base", value: application.salaryRange ?? "—", valueColor: nil),
            JobDetailField(label: "Posted Total Comp", value: application.postedTotalCompRange ?? "—", valueColor: nil),
            JobDetailField(label: "Expected Total Comp", value: application.expectedTotalCompRange ?? "—", valueColor: nil),
            JobDetailField(label: "Offer Total Comp", value: application.offerYearOneTotalCompText ?? "—", valueColor: nil)
        ]

        let workflowRows: [JobDetailField] = [
            JobDetailField(label: "Search Cycle", value: displayText(application.cycle?.name), valueColor: nil),
            JobDetailField(
                label: "Apply Queue",
                value: application.isQueuedForApplyLater ? "Queued" : "Not queued",
                valueColor: application.isQueuedForApplyLater ? DesignSystem.Colors.accent : nil
            ),
            optionalDateRow(label: "Applied On", value: application.appliedDate),
            optionalDateRow(label: "Posted On", value: application.postedAt)
        ].compactMap { $0 }

        let offerRows: [JobDetailField] = [
            optionalTextRow(
                label: "Equity (4yr est.)",
                value: application.offerEquityCompensation.map(application.currency.format)
            ),
            optionalTextRow(label: "PTO", value: application.offerPTOText),
            optionalTextRow(label: "Remote Policy", value: application.offerRemotePolicyText),
            optionalTextRow(label: "Growth Score", value: starText(for: application.offerGrowthScore)),
            optionalTextRow(label: "Team/Culture Fit", value: starText(for: application.offerTeamCultureFitScore))
        ].compactMap { $0 }

        return [
            JobDetailSection(title: "Compensation", rows: compensationRows),
            JobDetailSection(title: "Workflow", rows: workflowRows),
            JobDetailSection(title: "Offer Details", rows: offerRows)
        ].filter { !$0.rows.isEmpty }
    }

    private var secondaryRowCount: Int {
        secondarySections.reduce(0) { $0 + $1.rows.count }
    }

    private func displayText(_ value: String?) -> String {
        guard let value else { return "—" }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? "—" : trimmedValue
    }

    private func formattedDate(_ value: Date?) -> String {
        guard let value else { return "—" }
        return value.formatted(date: .long, time: .omitted)
    }

    private func optionalTextRow(label: String, value: String?) -> JobDetailField? {
        let displayValue = displayText(value)
        guard displayValue != "—" else { return nil }
        return JobDetailField(label: label, value: displayValue, valueColor: nil)
    }

    private func optionalDateRow(label: String, value: Date?) -> JobDetailField? {
        guard let value else { return nil }
        return JobDetailField(
            label: label,
            value: value.formatted(date: .long, time: .omitted),
            valueColor: nil
        )
    }

    private func starText(for score: Int?) -> String? {
        guard let score, score > 0 else { return nil }
        return String(repeating: "★", count: score)
    }
}

private struct JobDetailTableCard: View {
    let title: String
    let sections: [JobDetailSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)

            JobDetailTableContent(sections: sections)
        }
        .padding(18)
        .appCard(elevated: true)
    }
}

private struct JobDetailTableContent: View {
    let sections: [JobDetailSection]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.8)
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { rowIndex, row in
                            JobDetailTableRow(field: row)

                            if rowIndex < section.rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }

                if index < sections.count - 1 {
                    Divider()
                        .padding(.vertical, 16)
                }
            }
        }
    }
}

private struct JobDetailTableRow: View {
    let field: JobDetailField
    private let labelColumnWidth: CGFloat = 150

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(field.label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: labelColumnWidth, alignment: .leading)

            Text(field.value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(field.value == "—" ? .secondary : (field.valueColor ?? .primary))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 10)
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
        .appCard(elevated: true)
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
