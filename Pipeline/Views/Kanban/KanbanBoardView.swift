import SwiftUI
import SwiftData
import PipelineKit

struct KanbanBoardView: View {
    @Environment(\.modelContext) private var modelContext
    let applications: [JobApplication]
    @Binding var selectedApplication: JobApplication?

    @State private var viewModel = KanbanViewModel()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(KanbanViewModel.columns, id: \.rawValue) { status in
                    KanbanColumnView(
                        status: status,
                        applications: viewModel.applicationsForColumn(status, from: applications),
                        selectedApplication: $selectedApplication,
                        onDrop: { uuid, targetStatus in
                            guard let app = applications.first(where: { $0.id == uuid }) else { return }
                            viewModel.moveApplication(app, to: targetStatus, context: modelContext)
                        }
                    )
                }
            }
            .padding(16)
        }
    }
}
