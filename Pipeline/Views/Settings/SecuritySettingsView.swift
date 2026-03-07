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
            VStack(alignment: .leading, spacing: 18) {
                switch document {
                case .success(let content):
                    Text(content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
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
    enum LoadError: Error {
        case missingDocument
        case unreadableDocument
    }

    static func load() -> Result<AttributedString, LoadError> {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "md") else {
            return .failure(.missingDocument)
        }

        do {
            let markdown = try String(contentsOf: url, encoding: .utf8)
            let attributed = try AttributedString(
                markdown: markdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            )
            return .success(attributed)
        } catch {
            return .failure(.unreadableDocument)
        }
    }
}
