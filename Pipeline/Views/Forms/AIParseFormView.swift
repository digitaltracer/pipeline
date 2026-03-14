import SwiftUI
import PipelineKit

struct AIParseFormView: View {
    @Bindable var aiViewModel: AIParsingViewModel
    let onOpenSettings: (() -> Void)?
    var onReplayOnboarding: (() -> Void)? = nil
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
        .animation(.easeInOut(duration: 0.18), value: aiViewModel.isLoading)
        .animation(.easeInOut(duration: 0.18), value: aiViewModel.parsedData != nil)
    }

    private var configuredState: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.accent,
                                    DesignSystem.Colors.accent.opacity(0.70)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Smart Parse")
                        .font(.headline)

                    Text("Paste a job URL and let AI extract the details")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: aiViewModel.parseProvider.icon)
                    .foregroundColor(DesignSystem.Colors.accent)

                Text(providerSummary)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundColor(.secondary)

                TextField("https://linkedin.com/jobs/view/123456...", text: $aiViewModel.jobURL)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        triggerParse()
                    }
            }
            .appInput()

            Button(action: triggerParse) {
                HStack(spacing: 8) {
                    if aiViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }

                    Text(aiViewModel.isLoading ? "Parsing Job URL" : "Parse Job URL")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .controlSize(.large)
            .disabled(cannotParse)

            if let error = aiViewModel.error {
                errorBanner(error)
            }

            if aiViewModel.isLoading {
                loadingRow
            } else if let data = aiViewModel.parsedData {
                parsedPreview(data)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private var notConfiguredState: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))

                    Image(systemName: "key.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.orange)
                }
                .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Parse needs setup")
                        .font(.headline)

                    Text("Add a provider API key in Settings before parsing a job URL.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            #if os(macOS)
            if let onOpenSettings {
                Button("Open AI Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            } else {
                SettingsLink {
                    Text("Open AI Settings")
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
            #else
            Text("Open Settings to add an API key.")
                .font(.caption)
                .foregroundColor(.secondary)
            #endif

            VStack(alignment: .leading, spacing: 6) {
                Label("Add a provider key", systemImage: "key.fill")
                Label("Return here to parse job links", systemImage: "wand.and.stars")
                Label("Review the draft before saving", systemImage: "checkmark.shield")
            }
            .font(.caption)
            .foregroundColor(.secondary)

            if let onReplayOnboarding {
                Button("See Guided Tour Again", action: onReplayOnboarding)
                    .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .appCard(cornerRadius: 18, elevated: true, shadow: false)
    }

    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(DesignSystem.Colors.accent)

            Text("Fetching the page and extracting fields...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 2)
    }

    private func parsedPreview(_ data: ParsedJobData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Parsed Preview")
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(extractedFieldCount(from: data)) fields found")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ParsedFieldRow(label: "Company", value: data.companyName)
                ParsedFieldRow(label: "Role", value: data.role)
                ParsedFieldRow(label: "Location", value: data.location)

                if let salary = parsedSalaryText(from: data) {
                    ParsedFieldRow(label: "Salary", value: salary)
                }

                if !data.jobDescription.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(data.jobDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Text("Use Apply & Continue below to move this into Manual Entry before saving.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DesignSystem.Colors.surface(colorScheme))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)

            Text(message)
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
        }
        .padding(12)
        .background(Color.red.opacity(colorScheme == .dark ? 0.14 : 0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.red.opacity(colorScheme == .dark ? 0.24 : 0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var providerSummary: String {
        if aiViewModel.parseModel.isEmpty {
            return aiViewModel.parseProvider.rawValue
        }

        return "\(aiViewModel.parseProvider.rawValue) • \(aiViewModel.parseModel)"
    }

    private var cannotParse: Bool {
        aiViewModel.jobURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || aiViewModel.isLoading
    }

    private func triggerParse() {
        guard !cannotParse else { return }

        Task {
            await aiViewModel.parseJobURL()
        }
    }

    private func parsedSalaryText(from data: ParsedJobData) -> String? {
        if let min = data.salaryMin, let max = data.salaryMax {
            return data.currency.formatRange(min: min, max: max)
        }

        if let min = data.salaryMin {
            return "\(data.currency.format(min))+"
        }

        return nil
    }

    private func extractedFieldCount(from data: ParsedJobData) -> Int {
        var count = 0

        if !data.companyName.isEmpty { count += 1 }
        if !data.role.isEmpty { count += 1 }
        if !data.location.isEmpty { count += 1 }
        if data.salaryMin != nil || data.salaryMax != nil { count += 1 }
        if !data.jobDescription.isEmpty { count += 1 }

        return count
    }
}

private struct ParsedFieldRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading)

            Text(value.isEmpty ? "Not found" : value)
                .font(.subheadline)
                .foregroundColor(value.isEmpty ? .secondary : .primary)

            Spacer(minLength: 0)
        }
    }
}

#Preview {
    AIParseFormView(
        aiViewModel: AIParsingViewModel(),
        onOpenSettings: nil,
        onReplayOnboarding: nil
    )
}
