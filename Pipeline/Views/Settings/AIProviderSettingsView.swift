import SwiftUI

struct AIProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var apiKey: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Provider") {
                Picker("AI Provider", selection: $viewModel.selectedAIProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        Label(provider.rawValue, systemImage: provider.icon)
                            .tag(provider)
                    }
                }
                .onChange(of: viewModel.selectedAIProvider) { _, newProvider in
                    loadAPIKey(for: newProvider)
                    // Reset model to first available for new provider
                    if let firstModel = newProvider.models.first {
                        viewModel.selectedAIModel = firstModel
                    }
                }
            }

            Section("Model") {
                Picker("Model", selection: $viewModel.selectedAIModel) {
                    ForEach(viewModel.selectedAIProvider.models, id: \.self) { model in
                        Text(model).tag(model)
                    }
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
    }

    @ViewBuilder
    private var providerInfo: some View {
        switch viewModel.selectedAIProvider {
        case .openAI:
            VStack(alignment: .leading, spacing: 8) {
                Text("OpenAI provides GPT-4 and GPT-3.5 models.")
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

                Link("Get API Key", destination: URL(string: "https://console.anthropic.com/")!)
                    .font(.caption)
            }

        case .gemini:
            VStack(alignment: .leading, spacing: 8) {
                Text("Google Gemini offers powerful multimodal AI capabilities.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Link("Get API Key", destination: URL(string: "https://makersuite.google.com/app/apikey")!)
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

            // Hide confirmation after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                showingSaveConfirmation = false
            }
        } catch {
            saveError = "Failed to save API key: \(error.localizedDescription)"
            showingSaveConfirmation = false
        }
    }
}

#Preview {
    AIProviderSettingsView(viewModel: SettingsViewModel())
}
