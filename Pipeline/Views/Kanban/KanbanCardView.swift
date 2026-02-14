import SwiftUI
import PipelineKit

struct KanbanCardView: View {
    let application: JobApplication
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            CompanyAvatar(companyName: application.companyName, logoURL: application.googleS2FaviconURL(size: 64)?.absoluteString, size: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(application.role)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text(application.companyName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            PriorityFlag(priority: application.priority, size: 12)
        }
        .padding(10)
        .appCard(cornerRadius: 10, elevated: isSelected, shadow: isSelected)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : .clear, lineWidth: 2)
        )
        .onDrag {
            NSItemProvider(object: application.id.uuidString as NSString)
        }
    }
}
