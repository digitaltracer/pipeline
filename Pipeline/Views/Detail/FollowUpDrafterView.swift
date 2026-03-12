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

struct CoverLetterEditorView: View {
    @State var viewModel: CoverLetterEditorViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && !viewModel.hasResult {
                    loadingView
                } else if viewModel.hasResult {
                    editorView
                } else if let error = viewModel.error {
                    errorView(error)
                } else {
                    emptyView
                }
            }
            .navigationTitle("Cover Letter")
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 860, minHeight: 620, idealHeight: 760)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if viewModel.hasResult {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.copyToClipboard()
                        } label: {
                            Label("Copy Text", systemImage: "doc.on.doc")
                        }
                    }
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.saveTextVersion()
                        } label: {
                            Label("Save Text", systemImage: "square.and.arrow.down")
                        }
                    }
                    #if os(macOS)
                    ToolbarItem(placement: .automatic) {
                        Button {
                            Task { await viewModel.exportPDF() }
                        } label: {
                            Label(
                                viewModel.isExportingPDF ? "Exporting PDF..." : "Export PDF",
                                systemImage: "doc.richtext"
                            )
                        }
                        .disabled(viewModel.isExportingPDF)
                    }
                    #endif
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        Task { await viewModel.generate() }
                    } label: {
                        Label(
                            viewModel.hasResult ? "Regenerate All" : "Generate",
                            systemImage: viewModel.hasResult ? "arrow.clockwise" : "sparkles"
                        )
                    }
                    .disabled(viewModel.isLoading)
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Generating tailored cover letter...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(DesignSystem.Colors.accent.opacity(0.12))
                    .frame(width: 74, height: 74)
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundColor(DesignSystem.Colors.accent)
            }

            Text("Generate a tailored cover letter")
                .font(.headline)

            Text("Pipeline will use your latest tailored resume when available, fall back to your master resume, and map your experience directly to this job description.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)

            tonePicker
                .padding(.horizontal, 24)

            Button {
                Task { await viewModel.generate() }
            } label: {
                Label("Generate Cover Letter", systemImage: "sparkles")
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
            tonePicker
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

    private var editorView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerCard
                toneCard

                if let error = viewModel.error {
                    banner(
                        text: error,
                        systemImage: "exclamationmark.triangle.fill",
                        tint: .orange
                    )
                } else if let notice = viewModel.notice {
                    banner(
                        text: notice,
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                }

                sectionCard(
                    title: "Greeting",
                    icon: "hand.wave",
                    isBusy: viewModel.isRegenerating(.greeting)
                ) {
                    Task { await viewModel.regenerateSection(.greeting) }
                } content: {
                    sectionEditor(
                        text: Binding(
                            get: { viewModel.editableGreeting },
                            set: { viewModel.updateGreeting($0) }
                        ),
                        minHeight: 84
                    )
                }

                sectionCard(
                    title: "Hook",
                    icon: "bolt.fill",
                    isBusy: viewModel.isRegenerating(.hook)
                ) {
                    Task { await viewModel.regenerateSection(.hook) }
                } content: {
                    sectionEditor(
                        text: Binding(
                            get: { viewModel.editableHookParagraph },
                            set: { viewModel.updateHookParagraph($0) }
                        ),
                        minHeight: 140
                    )
                }

                ForEach(Array(viewModel.editableBodyParagraphs.enumerated()), id: \.offset) { index, _ in
                    sectionCard(
                        title: "Body Paragraph \(index + 1)",
                        icon: "text.alignleft",
                        isBusy: viewModel.isRegenerating(.body(index))
                    ) {
                        Task { await viewModel.regenerateSection(.body(index)) }
                    } content: {
                        sectionEditor(
                            text: Binding(
                                get: { viewModel.editableBodyParagraphs[index] },
                                set: { viewModel.updateBodyParagraph($0, at: index) }
                            ),
                            minHeight: 150
                        )
                    }
                }

                sectionCard(
                    title: "Closing",
                    icon: "signature",
                    isBusy: viewModel.isRegenerating(.closing)
                ) {
                    Task { await viewModel.regenerateSection(.closing) }
                } content: {
                    sectionEditor(
                        text: Binding(
                            get: { viewModel.editableClosingParagraph },
                            set: { viewModel.updateClosingParagraph($0) }
                        ),
                        minHeight: 110
                    )
                }
            }
            .padding(20)
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(DesignSystem.Colors.accent.opacity(0.12))
                        .frame(width: 54, height: 54)
                    Image(systemName: "doc.text")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(DesignSystem.Colors.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cover Letter Generator")
                        .font(.title3.weight(.semibold))
                    Text("For \(viewModel.companyName) · \(viewModel.roleTitle)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                if let sourceResumeLabel = viewModel.sourceResumeLabel {
                    chip(label: sourceResumeLabel, systemImage: "doc.text")
                }

                if let autosaveStatusText = viewModel.autosaveStatusText {
                    chip(label: autosaveStatusText, systemImage: "checkmark.circle")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private var toneCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Tone", systemImage: "waveform.and.magnifyingglass")
                .font(.headline)
            tonePicker
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private var tonePicker: some View {
        HStack(spacing: 10) {
            ForEach(CoverLetterTone.allCases) { tone in
                Button {
                    viewModel.updateTone(tone)
                } label: {
                    VStack(spacing: 6) {
                        Text(tone.displayName)
                            .font(.headline)
                        Text(tone.subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(
                                viewModel.editableTone == tone
                                    ? DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.18 : 0.1)
                                    : DesignSystem.Colors.surfaceElevated(colorScheme)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(
                                viewModel.editableTone == tone ? DesignSystem.Colors.accent : DesignSystem.Colors.stroke(colorScheme),
                                lineWidth: viewModel.editableTone == tone ? 1.5 : 1
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func banner(text: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundColor(tint)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(tint.opacity(colorScheme == .dark ? 0.14 : 0.09))
        )
    }

    private func chip(label: String, systemImage: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(label)
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(DesignSystem.Colors.surfaceElevated(colorScheme)))
    }

    private func sectionCard<Content: View>(
        title: String,
        icon: String,
        isBusy: Bool,
        onRegenerate: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)

                Spacer()

                Button {
                    onRegenerate()
                } label: {
                    if isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isBusy || viewModel.isLoading)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }

    private func sectionEditor(text: Binding<String>, minHeight: CGFloat) -> some View {
        TextEditor(text: text)
            .font(.body)
            .frame(minHeight: minHeight)
            #if os(macOS)
            .scrollContentBackground(.hidden)
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(DesignSystem.Colors.surfaceElevated(colorScheme).opacity(0.55))
            )
            #endif
    }
}
