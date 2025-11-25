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
    
    // MARK: - Capability Helpers
    
    /// Check if model has a specific capability
    func hasCapability(_ capability: String) -> Bool {
        return capabilities.contains(capability)
    }
    
    /// Check if model has reasoning capability
    var hasReasoning: Bool {
        return hasCapability("reasoning")
    }
    
    /// Check if model has vision capability
    var hasVision: Bool {
        return hasCapability("vision")
    }
    
    /// Check if model has function calling capability
    var hasFunctionCalling: Bool {
        return hasCapability("function-calling")
    }
}

/// Convenience initializers for hardcoded pricing data
extension PricingInfo {
    /// Groq pricing (typically free)
    static let groqFree = PricingInfo(
        inputPer1M: 0.0,
        outputPer1M: 0.0,
        source: "documentation"
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
    
    struct FormattedModelName {
        let displayName: String
        let provider: String?
        
        var fullName: String {
            if let provider = provider {
                return "\(displayName) (\(provider))"
            }
            return displayName
        }
    }
    
    /// Formats a model ID into structured components for display
    static func formatModelComponents(modelId: String, provider: String? = nil) -> FormattedModelName {
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
        
        let formatted = Self.formatModelName(modelName)
        let providerDisplay = providerPrefix.map { Self.mapProviderName($0).uppercased() }
        
        return FormattedModelName(displayName: formatted, provider: providerDisplay)
    }
    
    /// Formats a model ID into a human-readable display name
    /// Example: "x-ai/grok-code-fast-1" → "Grok Code Fast 1 (XAI)"
    static func formatModelDisplayName(modelId: String, provider: String? = nil) -> String {
        return formatModelComponents(modelId: modelId, provider: provider).fullName
    }
    
    private static func formatModelName(_ modelName: String) -> String {
        var name = modelName
        
        // Known model name mappings for cleaner display
        let knownModels: [String: String] = [
            "gpt-4o": "GPT-4o",
            "gpt-4o-mini": "GPT-4o Mini",
            "gpt-4-turbo": "GPT-4 Turbo",
            "gpt-4": "GPT-4",
            "gpt-3.5-turbo": "GPT-3.5 Turbo",
            "claude-3-5-sonnet": "Claude 3.5 Sonnet",
            "claude-3-5-haiku": "Claude 3.5 Haiku",
            "claude-3-opus": "Claude 3 Opus",
            "claude-3-sonnet": "Claude 3 Sonnet",
            "claude-3-haiku": "Claude 3 Haiku",
            "claude-sonnet-4": "Claude Sonnet 4",
            "claude-4-sonnet": "Claude Sonnet 4",
            "claude-opus-4": "Claude Opus 4",
            "claude-4-opus": "Claude Opus 4",
            "gemini-1.5-pro": "Gemini 1.5 Pro",
            "gemini-1.5-flash": "Gemini 1.5 Flash",
            "gemini-2.0-flash": "Gemini 2.0 Flash",
            "gemini-pro": "Gemini Pro",
            "llama-3.1-70b": "Llama 3.1 70B",
            "llama-3.1-8b": "Llama 3.1 8B",
            "llama-3-70b": "Llama 3 70B",
            "llama-3-8b": "Llama 3 8B",
            "mixtral-8x7b": "Mixtral 8x7B",
            "mistral-large": "Mistral Large",
            "mistral-medium": "Mistral Medium",
            "mistral-small": "Mistral Small",
            "deepseek-chat": "DeepSeek Chat",
            "deepseek-coder": "DeepSeek Coder",
            "deepseek-r1": "DeepSeek R1",
            "grok-2": "Grok 2",
            "grok-beta": "Grok Beta",
            "o1-preview": "O1 Preview",
            "o1-mini": "O1 Mini",
            "o1": "O1",
            "o3": "O3",
            "o3-mini": "O3 Mini",
        ]
        
        // Check for exact match first (case-insensitive)
        let lowerName = name.lowercased()
        for (key, value) in knownModels {
            if lowerName == key.lowercased() || lowerName.hasPrefix(key.lowercased()) {
                // Handle version suffixes like "-20241022"
                let suffix = String(name.dropFirst(key.count))
                if suffix.isEmpty || suffix.hasPrefix("-") || suffix.hasPrefix("@") {
                    return value
                }
            }
        }
        
        // Generic formatting: convert kebab-case/snake_case to Title Case
        // But preserve version numbers and special tokens
        let tokens = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
        
        let formatted = tokens.map { token -> String in
            let str = String(token)
            
            // Keep version numbers as-is (e.g., "3.5", "4o", "8x7b")
            if str.first?.isNumber == true || str.contains(".") {
                return str
            }
            
            // Keep size indicators uppercase (e.g., "70B", "8B")
            if str.hasSuffix("b") || str.hasSuffix("B"), let _ = Int(str.dropLast()) {
                return str.uppercased()
            }
            
            // Capitalize normally
            return str.capitalized
        }.joined(separator: " ")
        
        return formatted
    }
    
    private static func mapProviderName(_ provider: String) -> String {
        let mapping: [String: String] = [
            "x-ai": "XAI",
            "xai": "XAI",
            "anthropic": "ANTHROPIC",
            "openai": "OPENAI",
            "chatgpt": "OPENAI",
            "google": "GOOGLE",
            "gemini": "GOOGLE",
            "meta": "META",
            "meta-llama": "META",
            "mistralai": "MISTRAL",
            "mistral": "MISTRAL",
            "cohere": "COHERE",
            "perplexity": "PERPLEXITY",
            "deepseek": "DEEPSEEK",
            "qwen": "QWEN",
            "nvidia": "NVIDIA",
            "groq": "GROQ",
            "ollama": "OLLAMA",
            "openrouter": "OPENROUTER",
            "lmstudio": "LMSTUDIO",
            "claude": "ANTHROPIC",
        ]
        return mapping[provider.lowercased()] ?? provider.uppercased()
    }
}
