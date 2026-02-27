import SwiftUI
import SwiftData
import PipelineKit

struct KanbanColumnView: View {
    let status: ApplicationStatus
    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?
    let onDrop: (UUID, ApplicationStatus) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Column header
            HStack(spacing: 8) {
                Image(systemName: status.icon)
                    .font(.system(size: 13))
                    .foregroundColor(status.color)

                Text(status.displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text("\(applications.count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(DesignSystem.Colors.inputBackground(colorScheme))
                    )

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            // Color top border
            Rectangle()
                .fill(status.color)
                .frame(height: 2)

            // Cards
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(applications) { application in
                        KanbanCardView(
                            application: application,
                            isSelected: selectedApplication?.id == application.id
                        )
                        .onTapGesture {
                            openDetails(for: application)
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 300)
        .background(DesignSystem.Colors.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
        .onDrop(of: [.plainText], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { nsString, _ in
                guard let uuidString = nsString as? String,
                      let uuid = UUID(uuidString: uuidString) else { return }
                DispatchQueue.main.async {
                    onDrop(uuid, status)
                }
            }
            return true
        }
    }

    private func openDetails(for application: JobApplication) {
        selectedApplication = application
    }
}
