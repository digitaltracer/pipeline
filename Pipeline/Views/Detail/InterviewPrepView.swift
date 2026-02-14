import SwiftUI
import PipelineKit

struct InterviewPrepView: View {
    @State var viewModel: InterviewPrepViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let result = viewModel.result {
                    resultView(result)
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Interview Prep")
            #if os(macOS)
            .frame(minWidth: 500, idealWidth: 600, minHeight: 450, idealHeight: 600)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if viewModel.hasResult {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            copyAll()
                        } label: {
                            Label("Copy All", systemImage: "doc.on.doc")
                        }
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.generate() }
                    } label: {
                        Label(
                            viewModel.hasResult ? "Regenerate" : "Generate",
                            systemImage: viewModel.hasResult ? "arrow.clockwise" : "sparkles"
                        )
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating interview prep...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Generate AI-powered interview prep materials")
                .font(.headline)
            Text("Get likely questions, talking points, and company research tailored to this role.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Generate Prep", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Try Again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Result

    private func resultView(_ result: InterviewPrepResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Likely Questions
                if !result.likelyQuestions.isEmpty {
                    sectionView(
                        title: "Likely Questions",
                        icon: "questionmark.circle.fill",
                        color: .blue
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(result.likelyQuestions.enumerated()), id: \.offset) { index, question in
                                HStack(alignment: .top, spacing: 10) {
                                    Text("\(index + 1).")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .trailing)
                                    Text(question)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                // Talking Points
                if !result.talkingPoints.isEmpty {
                    sectionView(
                        title: "Talking Points",
                        icon: "text.bubble.fill",
                        color: .green
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(result.talkingPoints.enumerated()), id: \.offset) { _, point in
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                        .padding(.top, 2)
                                    Text(point)
                                        .font(.subheadline)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                    }
                }

                // Company Research
                if !result.companyResearchSummary.isEmpty {
                    sectionView(
                        title: "Company Research",
                        icon: "building.2.fill",
                        color: .purple
                    ) {
                        Text(result.companyResearchSummary)
                            .font(.subheadline)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(20)
        }
    }

    private func sectionView<Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
    }

    // MARK: - Actions

    private func copyAll() {
        guard let result = viewModel.result else { return }

        var text = "INTERVIEW PREP\n\n"

        if !result.likelyQuestions.isEmpty {
            text += "LIKELY QUESTIONS\n"
            for (i, q) in result.likelyQuestions.enumerated() {
                text += "\(i + 1). \(q)\n"
            }
            text += "\n"
        }

        if !result.talkingPoints.isEmpty {
            text += "TALKING POINTS\n"
            for point in result.talkingPoints {
                text += "- \(point)\n"
            }
            text += "\n"
        }

        if !result.companyResearchSummary.isEmpty {
            text += "COMPANY RESEARCH\n\(result.companyResearchSummary)\n"
        }

        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }
}
