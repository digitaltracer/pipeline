import SwiftUI

struct JobDescriptionView: View {
    let description: String
    @State private var isExpanded = false

    private let previewLineLimit = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Job Description", systemImage: "doc.text")
                    .font(.headline)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Text(isExpanded ? "Show Less" : "Show More")
                        .font(.caption)
                        .foregroundColor(DesignSystem.Colors.accent)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(isExpanded ? nil : previewLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }
}

#Preview {
    JobDescriptionView(
        description: """
        We are looking for an experienced iOS developer to join our team. You will be responsible for developing and maintaining our iOS applications.

        Requirements:
        - 5+ years of iOS development experience
        - Strong knowledge of Swift and SwiftUI
        - Experience with Core Data and CloudKit
        - Excellent problem-solving skills
        - Strong communication skills

        Nice to have:
        - Experience with macOS development
        - Knowledge of CI/CD pipelines
        - Open source contributions
        """
    )
    .padding()
}
