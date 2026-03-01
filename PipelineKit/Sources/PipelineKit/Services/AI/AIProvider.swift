import Foundation

public enum AIProvider: String, CaseIterable, Identifiable, Sendable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"
    case gemini = "Google Gemini"

    public var id: String { providerID }

    public var descriptor: AIProviderDescriptor {
        AIProviderRegistry.descriptor(for: self)
    }

    public var providerID: String { descriptor.providerID }
    public var icon: String { descriptor.icon }
    public var defaultModels: [String] { descriptor.defaultModels }
    public var models: [String] { defaultModels }
    public var keychainKey: String { descriptor.keychainAccount }
    public var aboutText: String { descriptor.aboutText }
    public var apiKeyURL: String { descriptor.apiKeyURL }
}

public struct AIProviderDescriptor: Sendable {
    public let provider: AIProvider
    public let providerID: String
    public let icon: String
    public let keychainAccount: String
    public let aboutText: String
    public let apiKeyURL: String
    public let defaultModels: [String]

    public init(
        provider: AIProvider,
        providerID: String,
        icon: String,
        keychainAccount: String,
        aboutText: String,
        apiKeyURL: String,
        defaultModels: [String]
    ) {
        self.provider = provider
        self.providerID = providerID
        self.icon = icon
        self.keychainAccount = keychainAccount
        self.aboutText = aboutText
        self.apiKeyURL = apiKeyURL
        self.defaultModels = defaultModels
    }
}

public enum AIProviderRegistry {
    public static let allDescriptors: [AIProviderDescriptor] = [
        AIProviderDescriptor(
            provider: .openAI,
            providerID: "openai",
            icon: "brain",
            keychainAccount: "com.pipeline.openai-api-key",
            aboutText: "OpenAI provides GPT and reasoning models for job posting parsing.",
            apiKeyURL: "https://platform.openai.com/api-keys",
            defaultModels: [
                "gpt-5",
                "gpt-5-mini",
                "gpt-4.1",
                "gpt-4o",
                "o4-mini"
            ]
        ),
        AIProviderDescriptor(
            provider: .anthropic,
            providerID: "anthropic",
            icon: "sparkles",
            keychainAccount: "com.pipeline.anthropic-api-key",
            aboutText: "Anthropic provides Claude models with strong reasoning and structured output.",
            apiKeyURL: "https://console.anthropic.com/",
            defaultModels: [
                "claude-sonnet-4-5",
                "claude-opus-4-1",
                "claude-sonnet-4",
                "claude-3-7-sonnet-latest",
                "claude-3-5-haiku-latest"
            ]
        ),
        AIProviderDescriptor(
            provider: .gemini,
            providerID: "gemini",
            icon: "wand.and.stars",
            keychainAccount: "com.pipeline.gemini-api-key",
            aboutText: "Google Gemini offers fast and capable multimodal models.",
            apiKeyURL: "https://ai.google.dev/aistudio",
            defaultModels: [
                "gemini-2.5-pro",
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.0-flash",
                "gemini-2.0-flash-lite"
            ]
        )
    ]

    public static func descriptor(for provider: AIProvider) -> AIProviderDescriptor {
        allDescriptors.first { $0.provider == provider } ?? allDescriptors[0]
    }
}
