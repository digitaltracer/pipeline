import SwiftUI
import PipelineKit

struct SecuritySettingsView: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(AppLockCoordinator.self) private var appLockCoordinator

    var body: some View {
        Form {
            appLockSection
            privacySection
        }
        .formStyle(.grouped)
        .navigationTitle("Security")
        .task {
            appLockCoordinator.refreshAvailability()
        }
        .alert("App Lock", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                appLockCoordinator.dismissError()
            }
        } message: {
            Text(appLockCoordinator.errorMessage ?? "")
        }
    }

    private var appLockSection: some View {
        Section {
            Toggle("Require device authentication", isOn: appLockBinding)

            Label(
                viewModel.appLockEnabled ? "App lock is on" : "App lock is off",
                systemImage: viewModel.appLockEnabled ? "lock.fill" : "lock.open"
            )
            .foregroundColor(viewModel.appLockEnabled ? .green : .secondary)

            Label(
                appLockCoordinator.availability.supportSummary,
                systemImage: appLockCoordinator.availability.isAvailable ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
            )
            .foregroundColor(appLockCoordinator.availability.isAvailable ? .secondary : .orange)
        } footer: {
            Text("When enabled, Pipeline locks as soon as the app leaves the foreground and requires Face ID, Touch ID, or your device passcode before showing job-search data again.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink {
                PrivacyPolicyView()
            } label: {
                Label("Review Privacy Policy", systemImage: "hand.raised.fill")
            }
        } header: {
            Text("Privacy Policy")
        } footer: {
            Text("The policy is bundled with the app so it is always available offline.")
        }
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.appLockEnabled },
            set: { isEnabled in
                Task {
                    await appLockCoordinator.setAppLockEnabled(isEnabled)
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { appLockCoordinator.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appLockCoordinator.dismissError()
                }
            }
        )
    }
}

struct SecuritySettingsContent: View {
    @Bindable var viewModel: SettingsViewModel
    @Environment(AppLockCoordinator.self) private var appLockCoordinator
    @State private var showingPrivacyPolicy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsFormSectionCard(
                title: "App Lock",
                subtitle: "Require Face ID, Touch ID, or your device passcode before Pipeline shows job-search data after the app leaves the foreground.",
                icon: "lock.shield.fill"
            ) {
                Toggle("Require device authentication", isOn: appLockBinding)
                    .tint(DesignSystem.Colors.accent)

                Label(
                    viewModel.appLockEnabled ? "App lock is on." : "App lock is off.",
                    systemImage: viewModel.appLockEnabled ? "lock.fill" : "lock.open"
                )
                .foregroundColor(viewModel.appLockEnabled ? .green : .secondary)

                Label(
                    appLockCoordinator.availability.supportSummary,
                    systemImage: appLockCoordinator.availability.isAvailable ? "checkmark.shield.fill" : "exclamationmark.shield.fill"
                )
                .foregroundColor(appLockCoordinator.availability.isAvailable ? .secondary : .orange)
            }

            SettingsFormSectionCard(
                title: "Privacy Policy",
                subtitle: "Review how Pipeline stores, syncs, and shares your data with AI providers you configure.",
                icon: "hand.raised.fill"
            ) {
                Button("Open Privacy Policy") {
                    showingPrivacyPolicy = true
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
            }
        }
        .task {
            appLockCoordinator.refreshAvailability()
        }
        .sheet(isPresented: $showingPrivacyPolicy) {
            NavigationStack {
                PrivacyPolicyView()
                    #if os(macOS)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showingPrivacyPolicy = false
                            }
                        }
                    }
                    #endif
            }
        }
        .alert("App Lock", isPresented: errorAlertBinding) {
            Button("OK", role: .cancel) {
                appLockCoordinator.dismissError()
            }
        } message: {
            Text(appLockCoordinator.errorMessage ?? "")
        }
    }

    private var appLockBinding: Binding<Bool> {
        Binding(
            get: { viewModel.appLockEnabled },
            set: { isEnabled in
                Task {
                    await appLockCoordinator.setAppLockEnabled(isEnabled)
                }
            }
        )
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { appLockCoordinator.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    appLockCoordinator.dismissError()
                }
            }
        )
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let document = PrivacyPolicyDocument.load()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                switch document {
                case .success(let content):
                    privacyPolicyContent(content)
                case .failure(let error):
                    Text(errorMessage(for: error))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DesignSystem.Colors.contentBackground(colorScheme))
        .navigationTitle("Privacy Policy")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    @ViewBuilder
    private func privacyPolicyContent(_ document: PrivacyPolicyDocument.Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            if let updatedAt = document.lastUpdated {
                HStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .foregroundStyle(DesignSystem.Colors.accent)
                    Text(updatedAt)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule(style: .continuous)
                        .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                )
            }

            ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                VStack(alignment: .leading, spacing: 12) {
                    Text(section.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.primary)

                    ForEach(Array(section.blocks.enumerated()), id: \.offset) { _, block in
                        switch block {
                        case .paragraph(let text):
                            Text(text)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)

                        case .bulletList(let items):
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(items, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(DesignSystem.Colors.accent)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 7)

                                        Text(item)
                                            .font(.body)
                                            .foregroundStyle(.secondary)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DesignSystem.Colors.surfaceElevated(colorScheme))
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func errorMessage(for error: PrivacyPolicyDocument.LoadError) -> String {
        switch error {
        case .missingDocument:
            return "Pipeline could not load the bundled privacy policy."
        case .unreadableDocument:
            return "Pipeline could not read the bundled privacy policy."
        }
    }
}

private enum PrivacyPolicyDocument {
    struct Content {
        let lastUpdated: String?
        let sections: [Section]
    }

    struct Section {
        let title: String
        let blocks: [Block]
    }

    enum Block {
        case paragraph(String)
        case bulletList([String])
    }

    enum LoadError: Error {
        case missingDocument
        case unreadableDocument
    }

    static func load() -> Result<Content, LoadError> {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md") else {
            return .failure(.missingDocument)
        }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            return .success(parse(markdown))
        } catch {
            return .failure(.unreadableDocument)
        }
    }

    private static func parse(_ markdown: String) -> Content {
        let lines = markdown.components(separatedBy: .newlines)
        var lastUpdated: String?
        var sections: [Section] = []
        var currentTitle: String?
        var currentBlocks: [Block] = []
        var paragraphLines: [String] = []
        var bulletItems: [String] = []

        func flushParagraph() {
            guard !paragraphLines.isEmpty else { return }
            let text = paragraphLines.joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                currentBlocks.append(.paragraph(text))
            }
            paragraphLines.removeAll()
        }

        func flushBullets() {
            guard !bulletItems.isEmpty else { return }
            currentBlocks.append(.bulletList(bulletItems))
            bulletItems.removeAll()
        }

        func flushSection() {
            flushParagraph()
            flushBullets()
            guard let currentTitle else { return }
            sections.append(Section(title: currentTitle, blocks: currentBlocks))
            currentBlocks.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if line.isEmpty {
                flushParagraph()
                flushBullets()
                continue
            }

            if line.hasPrefix("# ") {
                continue
            }

            if line.hasPrefix("Last updated:") {
                lastUpdated = String(line.dropFirst("Last updated:".count)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("## ") {
                flushSection()
                currentTitle = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                continue
            }

            if line.hasPrefix("- ") {
                flushParagraph()
                bulletItems.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushBullets()
            paragraphLines.append(line)
        }

        flushSection()

        return Content(lastUpdated: lastUpdated, sections: sections)
    }
}
