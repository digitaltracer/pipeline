import SwiftUI

struct AIProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var apiKey: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var saveError: String?
    @State private var customModelID: String = ""

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
        }
        .onChange(of: viewModel.selectedAIProvider) { _, newProvider in
            loadAPIKey(for: newProvider)
            if let firstModel = viewModel.availableModels(for: newProvider).first {
                viewModel.selectedAIModel = firstModel
            }
            customModelID = ""
        }
    }

    @ViewBuilder
    private var providerInfo: some View {
        switch viewModel.selectedAIProvider {
        case .openAI:
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI provides GPT models for job posting parsing.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Get API Key", destination: URL(string: "https://platform.openai.com/api-keys")!)
                    .font(.caption)
            }

        case .anthropic:
            VStack(alignment: .leading, spacing: 8) {
                Text("Anthropic provides Claude 3 models with excellent reasoning capabilities.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Get API Key", destination: URL(string: "https://platform.claude.com/")!)
                    .font(.caption)
            }

        case .gemini:
            VStack(alignment: .leading, spacing: 8) {
                Text("Google Gemini offers powerful multimodal AI capabilities.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Get API Key", destination: URL(string: "https://ai.google.dev/aistudio")!)
                    .font(.caption)
            }
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

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showingSaveConfirmation = false
            }
        } catch {
            saveError = "Failed to save API key: \(error.localizedDescription)"
            showingSaveConfirmation = false
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
            }

            // API Key Input
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                APIKeyInputField(
                    provider: viewModel.selectedAIProvider,
                    onSave: { checkAPIKey(for: viewModel.selectedAIProvider) }
                )
            }
        }
        .onAppear {
            checkAPIKey(for: viewModel.selectedAIProvider)
        }
        .onChange(of: viewModel.selectedAIProvider) { _, newProvider in
            checkAPIKey(for: newProvider)
            if let firstModel = viewModel.availableModels(for: newProvider).first {
                viewModel.selectedAIModel = firstModel
            }
            customModelID = ""
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

    var body: some View {
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
        .onAppear {
            loadKey()
        }
        .onChange(of: provider) { _, _ in
            loadKey()
        }
        .overlay(alignment: .trailing) {
            if showSuccess {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .padding(.trailing, 80)
            }
        }
    }

    private func loadKey() {
        do {
            apiKey = try KeychainService.shared.getAPIKey(for: provider)
        } catch {
            apiKey = ""
        }
    }

    private func saveKey() {
        do {
            try KeychainService.shared.saveAPIKey(apiKey, for: provider)
            showSuccess = true
            onSave()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                showSuccess = false
            }
        } catch {
            // Handle error silently or show alert
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
