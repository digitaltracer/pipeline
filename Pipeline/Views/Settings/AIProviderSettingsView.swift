import SwiftUI
import PipelineKit

struct AIProviderSettingsView: View {
    @Bindable var viewModel: SettingsViewModel

    @State private var apiKey: String = ""
    @State private var isAPIKeyVisible: Bool = false
    @State private var showingConnectionSuccess: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    @State private var statusError: String?
    @State private var isTestingConnection: Bool = false
    @State private var isSavingAPIKey: Bool = false
    @State private var validatedModels: [String] = []
    @State private var validatedProviderID: String?
    @State private var validatedKeyFingerprint: String?
    @State private var confirmationResetTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentValidationFingerprint: String {
        "\(viewModel.selectedAIProvider.providerID)|\(trimmedAPIKey)"
    }

    private var hasValidatedCurrentInput: Bool {
        !trimmedAPIKey.isEmpty &&
        validatedProviderID == viewModel.selectedAIProvider.providerID &&
        validatedKeyFingerprint == currentValidationFingerprint &&
        !validatedModels.isEmpty
    }

    var body: some View {
        Form {
            Section("Provider") {
                AIProviderSettingsContent(viewModel: viewModel)
            }

            Section("Model") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Model")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .foregroundColor(DesignSystem.Colors.accent)

                        Picker("Model", selection: $viewModel.selectedAIModel) {
                            ForEach(viewModel.availableModels(for: viewModel.selectedAIProvider), id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .appInput()

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

                HStack(spacing: 10) {
                    Button {
                        testConnection()
                    } label: {
                        if isTestingConnection {
                            Label("Testing...", systemImage: "hourglass")
                        } else {
                            Text("Test Connection")
                        }
                    }
                    .disabled(trimmedAPIKey.isEmpty || isTestingConnection || isSavingAPIKey)

                    Button {
                        saveAPIKey()
                    } label: {
                        if isSavingAPIKey {
                            Label("Saving...", systemImage: "hourglass")
                        } else {
                            Text("Save API Key")
                        }
                    }
                    .disabled(!hasValidatedCurrentInput || isTestingConnection || isSavingAPIKey)
                }

                if showingConnectionSuccess {
                    Label("Connection successful. You can now save this key.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                if showingSaveConfirmation {
                    Label("API key saved", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }

                if let error = statusError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            } header: {
                Text("API Key")
            } footer: {
                Text("Test the key first. Save is enabled only after a successful connection test for the current key and provider.")
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
            Task {
                await viewModel.refreshModelsIfNeeded(for: newProvider)
            }
        }
        .onChange(of: apiKey) { _, _ in
            invalidateValidatedState()
            showingSaveConfirmation = false
            showingConnectionSuccess = false
            statusError = nil
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
        invalidateValidatedState()
        showingSaveConfirmation = false
        showingConnectionSuccess = false
        statusError = nil
    }

    private func testConnection() {
        guard !isTestingConnection else { return }

        let provider = viewModel.selectedAIProvider
        let candidateKey = apiKey

        Task { @MainActor in
            isTestingConnection = true
            invalidateValidatedState()
            showingConnectionSuccess = false
            showingSaveConfirmation = false
            statusError = nil

            do {
                let models = try await viewModel.validateAPIKeyConnection(candidateKey, for: provider)
                validatedModels = models
                validatedProviderID = provider.providerID
                validatedKeyFingerprint = "\(provider.providerID)|\(candidateKey.trimmingCharacters(in: .whitespacesAndNewlines))"
                showingConnectionSuccess = true
            } catch {
                statusError = "Connection failed: \(error.localizedDescription)"
                showingSaveConfirmation = false
                showingConnectionSuccess = false
            }

            isTestingConnection = false
        }
    }

    private func saveAPIKey() {
        guard !isSavingAPIKey else { return }
        guard hasValidatedCurrentInput else { return }

        let provider = viewModel.selectedAIProvider
        let candidateKey = apiKey
        let validatedModels = validatedModels

        Task { @MainActor in
            isSavingAPIKey = true
            statusError = nil
            showingSaveConfirmation = false

            do {
                try viewModel.saveValidatedAPIKey(candidateKey, models: validatedModels, for: provider)

                showingSaveConfirmation = true
                confirmationResetTask?.cancel()
                confirmationResetTask = Task {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    showingSaveConfirmation = false
                }
            } catch {
                statusError = "Could not save API key: \(error.localizedDescription)"
                showingSaveConfirmation = false
            }

            isSavingAPIKey = false
        }
    }

    private func invalidateValidatedState() {
        validatedModels = []
        validatedProviderID = nil
        validatedKeyFingerprint = nil
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsFormSectionCard(
                title: "Provider",
                subtitle: "Select the model provider Pipeline uses for AI features.",
                icon: "brain.head.profile"
            ) {
                HStack(spacing: 12) {
                    ForEach(AIProvider.allCases) { provider in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.selectedAIProvider = provider
                                checkAPIKey(for: provider)
                            }
                        } label: {
                            ProviderCard(
                                provider: provider,
                                selectedModel: viewModel.preferredModel(for: provider),
                                isSelected: viewModel.selectedAIProvider == provider
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !hasAPIKey {
                SettingsFormSectionCard(
                    title: "API Key Needed",
                    subtitle: "Add a key to validate requests with \(viewModel.selectedAIProvider.rawValue).",
                    icon: "exclamationmark.triangle.fill"
                ) {
                    Label("No API key configured for \(viewModel.selectedAIProvider.rawValue)", systemImage: "lock.slash")
                        .font(.subheadline)
                        .foregroundColor(.orange)
                }
            }

            SettingsFormSectionCard(
                title: "Model",
                subtitle: "Choose a default model and refresh when providers add new options.",
                icon: "cpu.fill"
            ) {
                HStack(spacing: 8) {
                    Image(systemName: "cpu")
                        .foregroundColor(DesignSystem.Colors.accent)

                    Picker("Model", selection: $viewModel.selectedAIModel) {
                        ForEach(viewModel.availableModels(for: viewModel.selectedAIProvider), id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .appInput()

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

            SettingsFormSectionCard(
                title: "API Key",
                subtitle: "Stored securely in your system Keychain.",
                icon: "key.fill"
            ) {
                APIKeyInputField(
                    viewModel: viewModel,
                    provider: viewModel.selectedAIProvider,
                    onSave: {
                        checkAPIKey(for: viewModel.selectedAIProvider)
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
            Task {
                await viewModel.refreshModelsIfNeeded(for: newProvider)
            }
        }
    }

    private func checkAPIKey(for provider: AIProvider) {
        hasAPIKey = viewModel.hasAPIKey(for: provider)
    }
}

struct ProviderCard: View {
    let provider: AIProvider
    let selectedModel: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: provider.icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? DesignSystem.Colors.accent : .secondary)

            Text(provider.rawValue)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)

            Text(selectedModel)
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
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct APIKeyInputField: View {
    @Bindable var viewModel: SettingsViewModel
    let provider: AIProvider
    let onSave: () -> Void

    @State private var apiKey: String = ""
    @State private var isVisible: Bool = false
    @State private var showConnectionSuccess: Bool = false
    @State private var showSaveSuccess: Bool = false
    @State private var isTestingConnection: Bool = false
    @State private var isSaving: Bool = false
    @State private var errorMessage: String?
    @State private var validatedModels: [String] = []
    @State private var validatedProviderID: String?
    @State private var validatedKeyFingerprint: String?
    @State private var savedAPIKeys: [String] = []
    @State private var successResetTask: Task<Void, Never>?

    private var trimmedAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentValidationFingerprint: String {
        "\(provider.providerID)|\(trimmedAPIKey)"
    }

    private var hasValidatedCurrentInput: Bool {
        !trimmedAPIKey.isEmpty &&
        validatedProviderID == provider.providerID &&
        validatedKeyFingerprint == currentValidationFingerprint &&
        !validatedModels.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Group {
                    if isVisible {
                        TextField("Enter API key...", text: $apiKey)
                    } else {
                        SecureField("Enter API key...", text: $apiKey)
                    }
                }
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.secondary.opacity(0.18), lineWidth: 1)
                )

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)

                Button {
                    testConnection()
                } label: {
                    if isTestingConnection {
                        Label("Testing...", systemImage: "hourglass")
                    } else {
                        Text("Test Connection")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(trimmedAPIKey.isEmpty || isTestingConnection || isSaving)

                Button {
                    saveKey()
                } label: {
                    if isSaving {
                        Label("Adding...", systemImage: "hourglass")
                    } else {
                        Text("Add Key")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignSystem.Colors.accent)
                .disabled(!hasValidatedCurrentInput || isTestingConnection || isSaving)
            }

            if showConnectionSuccess {
                Label("Connection successful. Save is now enabled.", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if showSaveSuccess {
                Label("API key added", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Saved Keys (Waterfall Priority)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Top key is primary. Reorder to control fallback behavior.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if savedAPIKeys.isEmpty {
                    Text("No keys saved yet for \(provider.rawValue).")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(savedAPIKeys.enumerated()), id: \.offset) { index, key in
                        HStack(spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.monospacedDigit())
                                .fontWeight(.semibold)
                                .foregroundColor(index == 0 ? DesignSystem.Colors.accent : .secondary)
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle()
                                        .fill(index == 0 ? DesignSystem.Colors.accent.opacity(0.18) : Color.secondary.opacity(0.12))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(index == 0 ? "Primary Key" : "Fallback Key")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(maskedKey(key))
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if index != 0 {
                                Button("Make Primary") {
                                    makePrimary(at: index)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            Button {
                                moveKey(from: index, to: index - 1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(index == 0)

                            Button {
                                moveKey(from: index, to: index + 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(index == savedAPIKeys.count - 1)

                            Button(role: .destructive) {
                                removeKey(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
        .onAppear {
            loadKeys()
        }
        .onDisappear {
            successResetTask?.cancel()
            successResetTask = nil
        }
        .onChange(of: provider) { _, _ in
            loadKeys()
        }
        .onChange(of: apiKey) { _, _ in
            invalidateValidatedState()
            showConnectionSuccess = false
            showSaveSuccess = false
            errorMessage = nil
        }
    }

    private func loadKeys() {
        do {
            savedAPIKeys = try viewModel.apiKeys(for: provider)
            apiKey = ""
            errorMessage = nil
        } catch {
            apiKey = ""
            savedAPIKeys = []
            errorMessage = nil
        }
        invalidateValidatedState()
        showConnectionSuccess = false
        showSaveSuccess = false
    }

    private func testConnection() {
        guard !isTestingConnection else { return }

        let candidateKey = apiKey
        let currentProvider = provider

        Task { @MainActor in
            isTestingConnection = true
            invalidateValidatedState()
            showConnectionSuccess = false
            showSaveSuccess = false
            errorMessage = nil

            do {
                let models = try await viewModel.validateAPIKeyConnection(candidateKey, for: currentProvider)
                validatedModels = models
                validatedProviderID = currentProvider.providerID
                validatedKeyFingerprint = "\(currentProvider.providerID)|\(candidateKey.trimmingCharacters(in: .whitespacesAndNewlines))"
                showConnectionSuccess = true
            } catch {
                errorMessage = "Connection failed: \(error.localizedDescription)"
                showConnectionSuccess = false
            }

            isTestingConnection = false
        }
    }

    private func saveKey() {
        guard !isSaving else { return }
        guard hasValidatedCurrentInput else { return }

        let candidateKey = apiKey
        let currentProvider = provider
        let validatedModels = validatedModels

        Task { @MainActor in
            isSaving = true
            errorMessage = nil
            showSaveSuccess = false

            do {
                try viewModel.saveValidatedAPIKey(candidateKey, models: validatedModels, for: currentProvider)
                showSaveSuccess = true
                apiKey = ""
                savedAPIKeys = try viewModel.apiKeys(for: currentProvider)
                onSave()

                successResetTask?.cancel()
                successResetTask = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    showSaveSuccess = false
                }
            } catch {
                errorMessage = "Could not save API key: \(error.localizedDescription)"
                showSaveSuccess = false
            }

            isSaving = false
        }
    }

    private func invalidateValidatedState() {
        validatedModels = []
        validatedProviderID = nil
        validatedKeyFingerprint = nil
    }

    private func removeKey(at index: Int) {
        guard savedAPIKeys.indices.contains(index) else { return }

        do {
            var reordered = savedAPIKeys
            reordered.remove(at: index)
            try persistKeyOrder(reordered)
            showConnectionSuccess = false
            showSaveSuccess = false
            errorMessage = nil
        } catch {
            errorMessage = "Could not remove API key: \(error.localizedDescription)"
        }
    }

    private func moveKey(from source: Int, to destination: Int) {
        guard savedAPIKeys.indices.contains(source),
              savedAPIKeys.indices.contains(destination),
              source != destination else {
            return
        }

        do {
            var reordered = savedAPIKeys
            let moving = reordered.remove(at: source)
            reordered.insert(moving, at: destination)
            try persistKeyOrder(reordered)
            errorMessage = nil
        } catch {
            errorMessage = "Could not reorder API keys: \(error.localizedDescription)"
        }
    }

    private func makePrimary(at index: Int) {
        guard savedAPIKeys.indices.contains(index), index != 0 else { return }
        moveKey(from: index, to: 0)
    }

    private func persistKeyOrder(_ keys: [String]) throws {
        try viewModel.setAPIKeys(keys, for: provider)
        savedAPIKeys = try viewModel.apiKeys(for: provider)
        onSave()
    }

    private func maskedKey(_ key: String) -> String {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "****" }

        let prefixLength = min(4, trimmed.count)
        let suffixLength = min(4, max(0, trimmed.count - prefixLength))
        let prefix = String(trimmed.prefix(prefixLength))
        let suffix = String(trimmed.suffix(suffixLength))
        return "\(prefix)******\(suffix)"
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
