import SwiftUI

struct AIParseFormView: View {
    @Bindable var aiViewModel: AIParsingViewModel
    @Bindable var formViewModel: AddEditApplicationViewModel
    let onApplyParsedData: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if !aiViewModel.isConfigured {
                notConfiguredState
            } else {
                configuredState
            }
        }
        .onAppear { aiViewModel.refreshConfiguration() }
    }

    private var notConfiguredState: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.orange)
            }
            .frame(width: 54, height: 54)

            Text("AI Not Configured")
                .font(.headline)

            Text("Add your API key in settings to use AI-powered job parsing.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            #if os(macOS)
            SettingsLink {
                Text("Go to Settings")
                    .frame(width: 160)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            #else
            Text("Open Settings to add an API key.")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var configuredState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 34))
                    .foregroundStyle(DesignSystem.Colors.accent.gradient)

                Text("AI-Powered Job Parsing")
                    .font(.headline)

                Text("Paste a job posting URL and let AI extract the details for you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text("Job URL")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack(spacing: 10) {
                    TextField("https://linkedin.com/jobs/...", text: $aiViewModel.jobURL)
                        .textFieldStyle(.plain)
                        .appInput()

                    Button {
                        Task { await aiViewModel.parseJobURL() }
                    } label: {
                        if aiViewModel.isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Parse")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignSystem.Colors.accent)
                    .disabled(aiViewModel.jobURL.isEmpty || aiViewModel.isLoading)
                }
            }

            if let error = aiViewModel.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(12)
                .background(Color.red.opacity(colorScheme == .dark ? 0.14 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if let data = aiViewModel.parsedData {
                parsedDataPreview(data)
            }

            Spacer()

            if aiViewModel.parsedData != nil {
                Button {
                    aiViewModel.applyToViewModel(formViewModel)
                    onApplyParsedData()
                } label: {
                    Label("Apply & Continue to Form", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .controlSize(.large)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private func parsedDataPreview(_ data: AIParsingViewModel.ParsedJobData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Extracted Information")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                ParsedFieldRow(label: "Company", value: data.companyName)
                ParsedFieldRow(label: "Role", value: data.role)
                ParsedFieldRow(label: "Location", value: data.location)

                if let min = data.salaryMin, let max = data.salaryMax {
                    ParsedFieldRow(
                        label: "Salary",
                        value: data.currency.formatRange(min: min, max: max) ?? ""
                    )
                } else if let min = data.salaryMin {
                    ParsedFieldRow(label: "Salary", value: "\(data.currency.format(min))+")
                }

                if !data.jobDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(data.jobDescription)
                            .font(.caption)
                            .lineLimit(4)
                    }
                }
            }
            .padding(14)
            .appCard(cornerRadius: 14, elevated: true, shadow: false)
        }
        .padding(16)
        .appCard(cornerRadius: 16, elevated: true, shadow: false)
    }
}

struct ParsedFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value.isEmpty ? "Not found" : value)
                .font(.subheadline)
                .foregroundColor(value.isEmpty ? .secondary : .primary)
        }
    }
}

#Preview {
    AIParseFormView(
        aiViewModel: AIParsingViewModel(),
        formViewModel: AddEditApplicationViewModel(),
        onApplyParsedData: {}
    )
}
