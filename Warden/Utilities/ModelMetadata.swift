import Foundation

/// Pricing information for a model
struct PricingInfo: Codable {
    let inputPer1M: Double?          // cost per 1M input tokens (USD)
    let outputPer1M: Double?         // cost per 1M output tokens (USD)
    let source: String               // "openai-api", "anthropic-api", "groq-api", "documentation"
    let lastFetchedDate: Date        // when we last verified this price
    
    init(inputPer1M: Double?, outputPer1M: Double?, source: String) {
        self.inputPer1M = inputPer1M
        self.outputPer1M = outputPer1M
        self.source = source
        self.lastFetchedDate = Date()
    }
}

/// Source of metadata
enum MetadataSource: String, Codable {
    case apiResponse          // extracted from provider API response
    case providerDocumentation // manually sourced from official docs
    case cachedStale          // cached but >30 days old (show warning)
    case unknown              // couldn't fetch
}

/// Cost level for display
enum CostLevel: String, Codable {
    case cheap = "cheap"           // <$1/1M input
    case standard = "standard"     // $1-$10/1M input
    case expensive = "expensive"   // >$10/1M input
}

/// Latency estimate
enum LatencyLevel: String, Codable {
    case fast = "fast"
    case medium = "medium"
    case slow = "slow"
}

/// Complete metadata for a model
struct ModelMetadata: Codable {
    let modelId: String
    let provider: String
    let pricing: PricingInfo?
    let maxContextTokens: Int?
    let capabilities: [String]       // ["vision", "reasoning", "function-calling"]
    let latency: LatencyLevel?
    let costLevel: CostLevel?
    let lastUpdated: Date
    let source: MetadataSource
    
    /// Check if metadata is stale (>30 days old)
    var isStale: Bool {
        let daysSince = Calendar.current.dateComponents([.day], from: lastUpdated, to: Date()).day ?? 0
        return daysSince > 30
    }
    
    /// Get display-friendly cost indicator
    var costIndicator: String {
        switch costLevel {
        case .cheap:
            return "$"
        case .standard:
            return "$$"
        case .expensive:
            return "$$$"
        case .none:
            return "—"
        }
    }
    
    /// Check if pricing data is available
    var hasPricing: Bool {
        return pricing != nil && (pricing?.inputPer1M != nil || pricing?.outputPer1M != nil)
    }
}

/// Convenience initializers for hardcoded pricing data
extension PricingInfo {
    /// OpenAI pricing (manually maintained from https://openai.com/pricing)
    static let openaiGPT4Turbo = PricingInfo(
        inputPer1M: 0.01,
        outputPer1M: 0.03,
        source: "openai-api"
    )
    
    static let openaiGPT4o = PricingInfo(
        inputPer1M: 0.005,
        outputPer1M: 0.015,
        source: "openai-api"
    )
    
    static let openaiGPT35Turbo = PricingInfo(
        inputPer1M: 0.0005,
        outputPer1M: 0.0015,
        source: "openai-api"
    )
    
    static let openaiGPT4oMini = PricingInfo(
        inputPer1M: 0.00015,
        outputPer1M: 0.0006,
        source: "openai-api"
    )
    
    /// Anthropic pricing (from https://www.anthropic.com/pricing)
    static let claudeOpus = PricingInfo(
        inputPer1M: 0.015,
        outputPer1M: 0.075,
        source: "anthropic-api"
    )
    
    static let claudeSonnet = PricingInfo(
        inputPer1M: 0.003,
        outputPer1M: 0.015,
        source: "anthropic-api"
    )
    
    static let claudeHaiku = PricingInfo(
        inputPer1M: 0.00080,
        outputPer1M: 0.0024,
        source: "anthropic-api"
    )
    
    /// Groq pricing (typically free)
    static let groqFree = PricingInfo(
        inputPer1M: 0.0,
        outputPer1M: 0.0,
        source: "documentation"
    )
    
    /// Mistral pricing
    static let mistralSmall = PricingInfo(
        inputPer1M: 0.00014,
        outputPer1M: 0.00042,
        source: "mistral-api"
    )
    
    static let mistralMedium = PricingInfo(
        inputPer1M: 0.00024,
        outputPer1M: 0.00072,
        source: "mistral-api"
    )
    
    static let mistralLarge = PricingInfo(
        inputPer1M: 0.0008,
        outputPer1M: 0.0024,
        source: "mistral-api"
    )
    
    /// Google Gemini pricing
    static let geminiFlash = PricingInfo(
        inputPer1M: 0.075,
        outputPer1M: 0.30,
        source: "google-cloud-pricing"
    )
    
    static let geminipro = PricingInfo(
        inputPer1M: 0.50,
        outputPer1M: 1.50,
        source: "google-cloud-pricing"
    )
    
    /// xAI pricing
    static let groxPro = PricingInfo(
        inputPer1M: 0.05,
        outputPer1M: 0.15,
        source: "xai-api"
    )
    
    /// Perplexity pricing
    static let perplexityProOnline = PricingInfo(
        inputPer1M: 0.003,
        outputPer1M: 0.003,
        source: "perplexity-api"
    )
    
    /// DeepSeek pricing
    static let deepseekChat = PricingInfo(
        inputPer1M: 0.00014,
        outputPer1M: 0.00028,
        source: "deepseek-api"
    )
    
    /// Claude pricing (newer models - January 2025 pricing)
    static let claudeOpus25 = PricingInfo(
        inputPer1M: 0.015,
        outputPer1M: 0.075,
        source: "anthropic-api"
    )
    
    static let claudeSonnet4 = PricingInfo(
        inputPer1M: 0.003,
        outputPer1M: 0.015,
        source: "anthropic-api"
    )
}

// MARK: - Helper for self-hosted/free models

extension ModelMetadata {
    /// Create free model metadata for self-hosted providers
    static func freeSelfHosted(modelId: String, provider: String, context: Int?, capabilities: [String] = []) -> ModelMetadata {
        return ModelMetadata(
            modelId: modelId,
            provider: provider,
            pricing: PricingInfo(inputPer1M: 0.0, outputPer1M: 0.0, source: "self-hosted"),
            maxContextTokens: context,
            capabilities: capabilities,
            latency: nil,
            costLevel: .cheap,
            lastUpdated: Date(),
            source: .providerDocumentation
        )
    }
    
    // MARK: - Model Name Formatting
    
    /// Formats a model ID into a human-readable display name
    /// Example: "x-ai/grok-code-fast-1" → "Grok Code Fast 1 (xAI)"
    static func formatModelDisplayName(modelId: String, provider: String? = nil) -> String {
        // Split by "/" if OpenRouter-style format
        let parts = modelId.split(separator: "/")
        let modelName: String
        let providerPrefix: String?
        
        if parts.count == 2 {
            providerPrefix = String(parts[0])
            modelName = String(parts[1])
        } else {
            providerPrefix = provider
            modelName = modelId
        }
        
        // Convert kebab-case/snake_case to Title Case
        let formatted = modelName
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
        
        // Add provider suffix if available
        if let prefix = providerPrefix {
            let friendlyProvider = Self.mapProviderName(prefix)
            return "\(formatted) (\(friendlyProvider))"
        }
        
        return formatted
    }
    
    private static func mapProviderName(_ provider: String) -> String {
        let mapping: [String: String] = [
            "x-ai": "xAI",
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "google": "Google",
            "meta": "Meta",
            "mistralai": "Mistral AI",
            "cohere": "Cohere",
            "perplexity": "Perplexity",
            "deepseek": "DeepSeek",
            "qwen": "Qwen",
            "nvidia": "NVIDIA"
        ]
        return mapping[provider.lowercased()] ?? provider.capitalized
    }
}
