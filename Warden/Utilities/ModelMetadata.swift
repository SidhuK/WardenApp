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
}
