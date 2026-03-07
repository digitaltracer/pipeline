import SwiftUI
import PipelineKit

struct FollowUpDrafterView: View {
    @State var viewModel: FollowUpDrafterViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var showingLogSentEmail = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if viewModel.hasResult {
                    editorView
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Draft Follow-up")
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
                            showingLogSentEmail = true
                        } label: {
                            Label("Log Sent", systemImage: "checkmark.circle")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.copyToClipboard()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            if let url = viewModel.mailtoURL {
                                openURL(url)
                            }
                        } label: {
                            Label("Mail", systemImage: "envelope")
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
        .sheet(isPresented: $showingLogSentEmail) {
            LogSentEmailView(
                application: viewModel.applicationForLogging,
                suggestedSubject: viewModel.editableSubject,
                suggestedBody: viewModel.editableBody
            )
        }
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Drafting follow-up email...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("Generate a follow-up email")
                .font(.headline)
            Text("AI will draft a professional follow-up email based on your application details and interview history.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if viewModel.daysSinceLastContact > 0 {
                Text("\(viewModel.daysSinceLastContact) days since last contact")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Draft Email", systemImage: "sparkles")
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

    // MARK: - Editor

    private var editorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Subject
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.alignleft")
                            .foregroundColor(.blue)
                        Text("Subject")
                            .font(.headline)
                    }

                    TextField("Subject", text: $viewModel.editableSubject)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)

                // Body
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "text.justify.left")
                            .foregroundColor(.green)
                        Text("Body")
                            .font(.headline)
                    }

                    TextEditor(text: $viewModel.editableBody)
                        .font(.body)
                        .frame(minHeight: 250)
                        #if os(macOS)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(DesignSystem.Colors.surfaceElevated(colorScheme).opacity(0.5))
                        )
                        #endif
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard(cornerRadius: 14, elevated: true, shadow: false)

                // Actions
                HStack(spacing: 12) {
                    Button {
                        viewModel.copyToClipboard()
                    } label: {
                        Label("Copy to Clipboard", systemImage: "doc.on.doc")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        if let url = viewModel.mailtoURL {
                            openURL(url)
                        }
                    } label: {
                        Label("Open in Mail", systemImage: "envelope")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                }

                Button {
                    showingLogSentEmail = true
                } label: {
                    Label("Log Sent Email", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(16)
            }
            .padding(20)
        }
    }
}
