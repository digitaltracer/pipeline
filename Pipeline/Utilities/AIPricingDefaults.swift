import Foundation
import PipelineKit

struct AIPricingDefaults {
    struct RateDefinition {
        let providerID: String
        let model: String
        let inputUSDPerMillion: Double
        let outputUSDPerMillion: Double
    }

    static let defaultRates: [RateDefinition] = [
        // OpenAI
        .init(providerID: "openai", model: "gpt-5", inputUSDPerMillion: 1.25, outputUSDPerMillion: 10.0),
        .init(providerID: "openai", model: "gpt-5-mini", inputUSDPerMillion: 0.25, outputUSDPerMillion: 2.0),
        .init(providerID: "openai", model: "gpt-4.1", inputUSDPerMillion: 2.0, outputUSDPerMillion: 8.0),
        .init(providerID: "openai", model: "gpt-4o", inputUSDPerMillion: 2.5, outputUSDPerMillion: 10.0),
        .init(providerID: "openai", model: "o4-mini", inputUSDPerMillion: 1.1, outputUSDPerMillion: 4.4),

        // Anthropic
        .init(providerID: "anthropic", model: "claude-sonnet-4-5", inputUSDPerMillion: 3.0, outputUSDPerMillion: 15.0),
        .init(providerID: "anthropic", model: "claude-opus-4-1", inputUSDPerMillion: 15.0, outputUSDPerMillion: 75.0),
        .init(providerID: "anthropic", model: "claude-sonnet-4", inputUSDPerMillion: 3.0, outputUSDPerMillion: 15.0),
        .init(providerID: "anthropic", model: "claude-3-7-sonnet-latest", inputUSDPerMillion: 3.0, outputUSDPerMillion: 15.0),
        .init(providerID: "anthropic", model: "claude-3-5-haiku-latest", inputUSDPerMillion: 0.8, outputUSDPerMillion: 4.0),

        // Google Gemini
        .init(providerID: "gemini", model: "gemini-2.5-pro", inputUSDPerMillion: 1.25, outputUSDPerMillion: 10.0),
        .init(providerID: "gemini", model: "gemini-2.5-flash", inputUSDPerMillion: 0.3, outputUSDPerMillion: 2.5),
        .init(providerID: "gemini", model: "gemini-2.5-flash-lite", inputUSDPerMillion: 0.1, outputUSDPerMillion: 0.4),
        .init(providerID: "gemini", model: "gemini-2.0-flash", inputUSDPerMillion: 0.35, outputUSDPerMillion: 1.05),
        .init(providerID: "gemini", model: "gemini-2.0-flash-lite", inputUSDPerMillion: 0.075, outputUSDPerMillion: 0.3)
    ]
}
