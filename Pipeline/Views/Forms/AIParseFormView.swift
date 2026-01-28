import SwiftUI

struct AIParseFormView: View {
    @Bindable var aiViewModel: AIParsingViewModel
    @Bindable var formViewModel: AddEditApplicationViewModel
    let onApplyParsedData: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Instructions
            VStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.largeTitle)
                    .foregroundStyle(.blue.gradient)

                Text("AI-Powered Job Parsing")
                    .font(.headline)

                Text("Paste a job posting URL and let AI extract the details for you.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.top)

            // URL Input
            VStack(alignment: .leading, spacing: 8) {
                Text("Job URL")
                    .font(.headline)

                HStack {
                    TextField("https://example.com/job/12345", text: $aiViewModel.jobURL)
                        .textFieldStyle(.roundedBorder)

                    Button {
                        Task {
                            await aiViewModel.parseJobURL()
                        }
                    } label: {
                        if aiViewModel.isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Parse")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(aiViewModel.jobURL.isEmpty || aiViewModel.isLoading)
                }
            }
            .padding(.horizontal)

            // Error Display
            if let error = aiViewModel.error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal)
            }

            // Parsed Data Preview
            if let data = aiViewModel.parsedData {
                parsedDataPreview(data)
            }

            Spacer()

            // Apply Button
            if aiViewModel.parsedData != nil {
                Button {
                    aiViewModel.applyToViewModel(formViewModel)
                    onApplyParsedData()
                } label: {
                    Label("Apply & Continue to Form", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding()
            }
        }
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
            .padding()
            .background(Color(.textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal)
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
