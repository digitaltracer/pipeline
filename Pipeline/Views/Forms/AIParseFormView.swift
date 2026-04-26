import SwiftUI
import PipelineKit

struct AIParseFormView: View {
    @Bindable var aiViewModel: AIParsingViewModel
    let onOpenSettings: (() -> Void)?
    var onReplayOnboarding: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if !aiViewModel.isConfigured {
                notConfiguredState
            } else {
                configuredState
            }
        }
        .onAppear {
            aiViewModel.refreshConfiguration()
            aiViewModel.refreshPendingBrowserImport()
        }
        .onReceive(NotificationCenter.default.publisher(for: .pipelinePendingJobImportDidChange)) { _ in
            aiViewModel.refreshPendingBrowserImport()
        }
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

                    Text("Paste one or more job URLs and let AI extract the details")
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

            if let pending = aiViewModel.pendingBrowserImport {
                pendingBrowserImportBanner(pending)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .foregroundColor(.secondary)

                    Text("Job URL input")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("One URL per line")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                TextEditor(text: $aiViewModel.jobURL)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 76, maxHeight: 118)
                    .padding(8)
                    .background(DesignSystem.Colors.surface(colorScheme))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
                    )
            }

            Button(action: triggerParse) {
                HStack(spacing: 8) {
                    if aiViewModel.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }

                    Text(parseButtonTitle)
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

            if aiViewModel.browserHandoffURL != nil || aiViewModel.waitingForBrowserCapture {
                browserHandoffBanner
            }

            if aiViewModel.isLoading {
                loadingRow
            } else if let data = aiViewModel.parsedData {
                parsedPreview(data)
            }

            if !aiViewModel.batchResults.isEmpty {
                batchResultsView
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

    private func pendingBrowserImportBanner(_ pending: PendingJobImport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Browser capture ready", systemImage: "puzzlepiece.extension.fill")
                .font(.subheadline.weight(.semibold))

            Text(browserImportSummary(pending))
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Task { await aiViewModel.parsePendingBrowserImport() }
            } label: {
                Label("Review with AI in Pipeline", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .tint(DesignSystem.Colors.accent)
            .disabled(aiViewModel.isLoading)
        }
        .padding(12)
        .background(DesignSystem.Colors.accent.opacity(colorScheme == .dark ? 0.16 : 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var browserHandoffBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                aiViewModel.waitingForBrowserCapture ? "Waiting for browser capture" : "Open this page in your browser",
                systemImage: "safari"
            )
            .font(.subheadline.weight(.semibold))

            Text("Pipeline could not read enough content directly. Open the page in your browser, sign in if needed, then use the Pipeline extension to capture it.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let urlString = aiViewModel.browserHandoffURL,
               let url = URL(string: urlString) {
                Button {
                    aiViewModel.beginBrowserHandoff()
                    openURL(url)
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(colorScheme == .dark ? 0.16 : 0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private var batchResultsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Batch Results")
                .font(.subheadline.weight(.semibold))

            ForEach(aiViewModel.batchResults) { result in
                batchResultRow(result)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.surface(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DesignSystem.Colors.stroke(colorScheme), lineWidth: 1)
        )
    }

    private func batchResultRow(_ result: AIParsingViewModel.BatchParseResult) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: batchIcon(for: result))
                .foregroundColor(batchColor(for: result))
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(result.url)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(batchSubtitle(for: result))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            if case .parsed = result.state {
                Button("Review") {
                    aiViewModel.selectBatchResult(result)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else if case .needsBrowser = result.state,
                      let url = URL(string: result.url) {
                Button {
                    aiViewModel.browserHandoffURL = result.url
                    aiViewModel.beginBrowserHandoff()
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var providerSummary: String {
        if aiViewModel.parseModel.isEmpty {
            return aiViewModel.parseProvider.rawValue
        }

        return "\(aiViewModel.parseProvider.rawValue) • \(aiViewModel.parseModel)"
    }

    private var parseButtonTitle: String {
        if aiViewModel.isLoading {
            return "Parsing Job URL"
        }

        if aiViewModel.pendingBrowserImport != nil {
            return "Parse Pasted URL Instead"
        }

        return aiViewModel.jobURL.contains("\n") ? "Parse Job URLs" : "Parse Job URL"
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

    private func browserImportSummary(_ pending: PendingJobImport) -> String {
        let page = pending.capturedPage
        let title = page.title.isEmpty ? "Captured job page" : page.title
        let company = page.company.isEmpty ? page.url : page.company
        return "\(title) at \(company)"
    }

    private func batchIcon(for result: AIParsingViewModel.BatchParseResult) -> String {
        switch result.state {
        case .pending: return "circle"
        case .parsing: return "hourglass"
        case .parsed: return "checkmark.circle.fill"
        case .needsBrowser: return "safari"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func batchColor(for result: AIParsingViewModel.BatchParseResult) -> Color {
        switch result.state {
        case .pending, .parsing: return .secondary
        case .parsed: return .green
        case .needsBrowser: return .orange
        case .failed: return .red
        }
    }

    private func batchSubtitle(for result: AIParsingViewModel.BatchParseResult) -> String {
        switch result.state {
        case .pending:
            return "Waiting"
        case .parsing:
            return "Parsing"
        case .parsed(let data):
            return [data.companyName, data.role].filter { !$0.isEmpty }.joined(separator: " • ")
        case .needsBrowser(let message):
            return "Needs browser capture: \(message)"
        case .failed(let message):
            return message
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
