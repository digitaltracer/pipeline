import SwiftUI

struct AIProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var apiKey: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var saveError: String?
    @State private var customModelID: String = ""
    @State private var confirmationResetTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("Provider") {
                AIProviderSettingsContent(viewModel: viewModel)
            }

            Section("Model") {
                Picker("Model", selection: $viewModel.selectedAIModel) {
                    ForEach(viewModel.availableModels(for: viewModel.selectedAIProvider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                HStack {
                    TextField("Add custom model ID", text: $customModelID)
                        .textFieldStyle(.roundedBorder)

                    Button("Add") {
                        viewModel.addCustomModel(customModelID, for: viewModel.selectedAIProvider)
                        viewModel.selectedAIModel = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        customModelID = ""
                    }
                    .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                modelRefreshControls
            }

            Section {
                HStack {
                    if isAPIKeyVisible {
                        TextField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        SecureField("API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                    }

                    Button {
                        isAPIKeyVisible.toggle()
                    } label: {
                        Image(systemName: isAPIKeyVisible ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.plain)
                }

                Button("Save API Key") {
                    saveAPIKey()
                }
                .disabled(apiKey.isEmpty)

                if showingSaveConfirmation {
                    Label("API Key saved successfully", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                if let error = saveError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Your API key is stored securely in the system Keychain.")
            }

            Section {
                providerInfo
            } header: {
                Text("About \(viewModel.selectedAIProvider.rawValue)")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("AI Provider")
        .onAppear {
            loadAPIKey(for: viewModel.selectedAIProvider)
            Task {
                await viewModel.refreshModelsIfNeeded(for: viewModel.selectedAIProvider)
            }
        }
        .onDisappear {
            confirmationResetTask?.cancel()
            confirmationResetTask = nil
        }
        .onChange(of: viewModel.selectedAIProvider) { _, newProvider in
            loadAPIKey(for: newProvider)
            if let firstModel = viewModel.availableModels(for: newProvider).first {
                viewModel.selectedAIModel = firstModel
            }
            customModelID = ""
            Task {
                await viewModel.refreshModelsIfNeeded(for: newProvider)
            }
        }
    }

    @ViewBuilder
    private var providerInfo: some View {
        let descriptor = viewModel.selectedAIProvider.descriptor

        VStack(alignment: .leading, spacing: 8) {
            Text(descriptor.aboutText)
                .font(.caption)
                .foregroundColor(.secondary)

            Link("Get API Key", destination: URL(string: descriptor.apiKeyURL)!)
                .font(.caption)
        }
    }

    private func loadAPIKey(for provider: AIProvider) {
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
        } catch {
            apiKey = ""
        }
        showingSaveConfirmation = false
        saveError = nil
    }

    private func saveAPIKey() {
        do {
            try KeychainService.shared.saveAPIKey(apiKey, for: viewModel.selectedAIProvider)
            showingSaveConfirmation = true
            saveError = nil

            Task {
                await viewModel.refreshModels(for: viewModel.selectedAIProvider, force: true)
            }

            confirmationResetTask?.cancel()
            confirmationResetTask = Task {
                try? await Task.sleep(for: .seconds(3))
                guard !Task.isCancelled else { return }
                showingSaveConfirmation = false
            }
        } catch {
            saveError = "Failed to save API key: \(error.localizedDescription)"
            showingSaveConfirmation = false
        }
    }

    @ViewBuilder
    private var modelRefreshControls: some View {
        HStack(spacing: 10) {
            Button {
                Task { await viewModel.refreshModels(for: viewModel.selectedAIProvider, force: true) }
            } label: {
                if viewModel.isRefreshingModels(for: viewModel.selectedAIProvider) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Refresh Models", systemImage: "arrow.clockwise")
                }
            }
            .disabled(!viewModel.hasAPIKey(for: viewModel.selectedAIProvider))

            if let refreshedAt = viewModel.lastModelRefreshDate(for: viewModel.selectedAIProvider) {
                Text("Updated \(refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Using bundled defaults")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        if let refreshError = viewModel.modelRefreshError(for: viewModel.selectedAIProvider) {
            Text(refreshError)
                .font(.caption)
                .foregroundColor(.red)
        }
    }
}

struct AIProviderSettingsContent: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var hasAPIKey: Bool = false
    @State private var customModelID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Provider Cards
            HStack(spacing: 12) {
                ForEach(AIProvider.allCases) { provider in
                    ProviderCard(
                        provider: provider,
                        isSelected: viewModel.selectedAIProvider == provider
                    )
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.selectedAIProvider = provider
                            checkAPIKey(for: provider)
                        }
                    }
                }
            }

            // Warning Banner if no API Key
            if !hasAPIKey {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.yellow)

                    Text("No API key configured for \(viewModel.selectedAIProvider.rawValue)")
                        .font(.subheadline)

                    Spacer()
                }
                .padding(12)
                .background(Color.yellow.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Model Selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Model", selection: $viewModel.selectedAIModel) {
                    ForEach(viewModel.availableModels(for: viewModel.selectedAIProvider), id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .labelsHidden()

                HStack(spacing: 10) {
                    TextField("Custom model ID", text: $customModelID)
                        .textFieldStyle(.plain)
                        .appInput()

                    Button("Add") {
                        viewModel.addCustomModel(customModelID, for: viewModel.selectedAIProvider)
                        viewModel.selectedAIModel = customModelID.trimmingCharacters(in: .whitespacesAndNewlines)
                        customModelID = ""
                    }
                    .buttonStyle(.bordered)
                    .disabled(customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack(spacing: 10) {
                    Button {
                        Task { await viewModel.refreshModels(for: viewModel.selectedAIProvider, force: true) }
                    } label: {
                        if viewModel.isRefreshingModels(for: viewModel.selectedAIProvider) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Refresh Models", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.hasAPIKey(for: viewModel.selectedAIProvider))

                    if let refreshedAt = viewModel.lastModelRefreshDate(for: viewModel.selectedAIProvider) {
                        Text("Updated \(refreshedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Using bundled defaults")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if let refreshError = viewModel.modelRefreshError(for: viewModel.selectedAIProvider) {
                    Text(refreshError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                APIKeyInputField(
                    provider: viewModel.selectedAIProvider,
                    onSave: {
                        checkAPIKey(for: viewModel.selectedAIProvider)
                        Task {
                            await viewModel.refreshModels(for: viewModel.selectedAIProvider, force: true)
                        }
                    }
                )
            }
        }
        .onAppear {
            checkAPIKey(for: viewModel.selectedAIProvider)
            Task {
                await viewModel.refreshModelsIfNeeded(for: viewModel.selectedAIProvider)
            }
        }
        .onChange(of: viewModel.selectedAIProvider) { _, newProvider in
            checkAPIKey(for: newProvider)
            if let firstModel = viewModel.availableModels(for: newProvider).first {
                viewModel.selectedAIModel = firstModel
            }
            customModelID = ""
            Task {
                await viewModel.refreshModelsIfNeeded(for: newProvider)
            }
        }
    }

    private func checkAPIKey(for provider: AIProvider) {
        do {
            let key = try KeychainService.shared.getAPIKey(for: provider)
            hasAPIKey = !key.isEmpty
        } catch {
            hasAPIKey = false
        }
    }
}

struct ProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool

    private var modelPreview: String {
        provider.models.first ?? ""
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: provider.icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? DesignSystem.Colors.accent : .secondary)

            Text(provider.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)

            Text(modelPreview)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .appCard(cornerRadius: 14, elevated: true, shadow: false)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? DesignSystem.Colors.accent : Color.clear, lineWidth: 2)
        }
    }
}

struct APIKeyInputField: View {
    let provider: AIProvider
    let onSave: () -> Void

    @State private var apiKey: String = ""
    @State private var isVisible: Bool = false
    @State private var showSuccess: Bool = false
    @State private var errorMessage: String?
    @State private var successResetTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if isVisible {
                    TextField("Enter API key...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                } else {
                    SecureField("Enter API key...", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Button("Save") {
                    saveKey()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
            }
            .overlay(alignment: .trailing) {
                if showSuccess {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .padding(.trailing, 80)
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            loadKey()
        }
        .onDisappear {
            successResetTask?.cancel()
            successResetTask = nil
        }
        .onChange(of: provider) { _, _ in
            loadKey()
        }
    }

    private func loadKey() {
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
            errorMessage = nil
        } catch {
            apiKey = ""
            errorMessage = nil
        }
    }

    private func saveKey() {
        do {
            try KeychainService.shared.saveAPIKey(apiKey, for: provider)
            showSuccess = true
            errorMessage = nil
            onSave()

            successResetTask?.cancel()
            successResetTask = Task {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                showSuccess = false
            }
        } catch {
            errorMessage = "Failed to save API key: \(error.localizedDescription)"
            showSuccess = false
        }
    }
}

#Preview {
    VStack {
        AIProviderSettingsContent(viewModel: SettingsViewModel())
            .padding()

        Divider()

        AIProviderSettingsView(viewModel: SettingsViewModel())
    }
}
