import Foundation

// Note: ModelMetadata types are defined in ModelMetadata.swift

/// Protocol for fetching model metadata from providers
protocol ModelMetadataFetcher {
    /// Fetch metadata for all available models
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata]
    
    /// Fetch metadata for a specific model
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata
}

/// Factory for creating metadata fetchers for different providers
class ModelMetadataFetcherFactory {
    static func createFetcher(for provider: String) -> ModelMetadataFetcher {
        switch provider {
        case "chatgpt":
            return OpenAIMetadataFetcher()
        case "claude":
            return AnthropicMetadataFetcher()
        case "gemini":
            return GoogleMetadataFetcher()
        case "groq":
            return GroqMetadataFetcher()
        case "openrouter":
            return OpenRouterMetadataFetcher()
        case "mistral":
            return MistralMetadataFetcher()
        case "xai":
            return XAIMetadataFetcher()
        case "perplexity":
            return PerplexityMetadataFetcher()
        case "deepseek":
            return DeepSeekMetadataFetcher()
        case "ollama", "lmstudio":
            return LocalModelMetadataFetcher()
        default:
            return GenericMetadataFetcher(provider: provider)
        }
    }
}

// MARK: - OpenAI Fetcher

class OpenAIMetadataFetcher: ModelMetadataFetcher {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // OpenAI doesn't expose pricing via API, use hardcoded from docs
        var metadata: [String: ModelMetadata] = [:]
        
        // Common OpenAI models with pricing from https://openai.com/pricing
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "gpt-4-turbo": (PricingInfo.openaiGPT4Turbo, ["vision", "function-calling"], 128000),
            "gpt-4o": (PricingInfo.openaiGPT4o, ["vision", "function-calling"], 128000),
            "gpt-4o-mini": (PricingInfo.openaiGPT4oMini, ["vision", "function-calling"], 128000),
            "gpt-3.5-turbo": (PricingInfo.openaiGPT35Turbo, ["function-calling"], 16385),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "chatgpt",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .medium,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        // Fallback for unknown models
        return ModelMetadata(
            modelId: modelId,
            provider: "chatgpt",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Anthropic Fetcher

class AnthropicMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Anthropic doesn't expose pricing via API, use hardcoded from docs
        // See: https://docs.claude.com/en/docs/about-claude/pricing
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "claude-3-opus-20240229": (PricingInfo.claudeOpus, ["vision"], 200000),
            "claude-3-sonnet-20240229": (PricingInfo.claudeSonnet, ["vision"], 200000),
            "claude-3-haiku-20240307": (PricingInfo.claudeHaiku, ["vision"], 200000),
            "claude-3-5-sonnet-20241022": (PricingInfo.claudeSonnet4, ["vision"], 200000),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "claude",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .medium,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "claude",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Google Gemini Fetcher

class GoogleMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Google doesn't expose pricing via API, use hardcoded from Cloud Pricing
        // See: https://ai.google.dev/pricing
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo?, capabilities: [String], context: Int?)] = [
            "gemini-2.0-flash": (PricingInfo.geminiFlash, ["vision"], 1000000),
            "gemini-2.0-pro": (PricingInfo.geminipro, ["vision"], 1000000),
            "gemini-1.5-pro": (PricingInfo.geminipro, ["vision"], 1000000),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "gemini",
                pricing: data.0,
                maxContextTokens: data.context,
                capabilities: data.1,
                latency: .fast,
                costLevel: getCostLevel(for: data.0),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "gemini",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo?) -> CostLevel? {
        guard let pricing = pricing, let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Groq Fetcher

class GroqMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Groq models are free tier
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (capabilities: [String], context: Int?)] = [
            "mixtral-8x7b-32768": ([], 32768),
            "llama-3.1-70b-versatile": ([], 131072),
            "llama-3.3-70b-versatile": ([], 131072),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "groq",
                pricing: PricingInfo.groqFree,
                maxContextTokens: data.context,
                capabilities: data.0,
                latency: .fast,
                costLevel: .cheap,
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "groq",
            pricing: PricingInfo.groqFree,
            maxContextTokens: nil,
            capabilities: [],
            latency: .fast,
            costLevel: .cheap,
            lastUpdated: Date(),
            source: .providerDocumentation
        )
    }
}

// MARK: - OpenRouter Fetcher (Fetches from API!)

class OpenRouterMetadataFetcher: ModelMetadataFetcher {
    private let baseURL = "https://openrouter.ai/api/v1/models"
    
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // OpenRouter exposes all models with pricing via public API
        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "OpenRouterFetcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "OpenRouterFetcher", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        let decoder = JSONDecoder()
        let result = try decoder.decode(OpenRouterResponse.self, from: data)
        
        var metadata: [String: ModelMetadata] = [:]
        
        for model in result.data {
            // OpenRouter returns per-token pricing, convert to per-1M-tokens
            let inputPrice = (Double(model.pricing.prompt) ?? 0) * 1_000_000
            let outputPrice = (Double(model.pricing.completion) ?? 0) * 1_000_000
            
            let pricing = PricingInfo(
                inputPer1M: inputPrice,
                outputPer1M: outputPrice,
                source: "openrouter-api"
            )
            
            let capabilities = parseCapabilities(from: model)
            
            metadata[model.id] = ModelMetadata(
                modelId: model.id,
                provider: "openrouter",
                pricing: pricing,
                maxContextTokens: model.context_length,
                capabilities: capabilities,
                latency: estimateLatency(from: model),
                costLevel: getCostLevel(for: pricing),
                lastUpdated: Date(),
                source: .apiResponse
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "openrouter",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func parseCapabilities(from model: OpenRouterModel) -> [String] {
        var capabilities: [String] = []
        
        if model.architecture.input_modalities.contains("image") {
            capabilities.append("vision")
        }
        
        if model.supported_parameters.contains("reasoning") {
            capabilities.append("reasoning")
        }
        
        if model.supported_parameters.contains("tools") {
            capabilities.append("function-calling")
        }
        
        return capabilities
    }
    
    private func estimateLatency(from model: OpenRouterModel) -> LatencyLevel? {
        // Estimate based on model size/type
        if model.id.contains("mini") || model.id.contains("small") {
            return .fast
        } else if model.id.contains("large") || model.id.contains("opus") {
            return .slow
        }
        return .medium
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Mistral Fetcher (No public pricing API, use docs)

class MistralMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Mistral doesn't expose pricing via public API
        // Using documented pricing from https://mistral.ai/pricing
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "mistral-small": (PricingInfo.mistralSmall, [], 32000),
            "mistral-medium": (PricingInfo.mistralMedium, [], 32000),
            "mistral-large": (PricingInfo.mistralLarge, [], 32000),
            "mistral-large-latest": (PricingInfo.mistralLarge, [], 128000),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "mistral",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .medium,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "mistral",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - xAI Fetcher (Grok)

class XAIMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // xAI pricing from https://docs.x.ai/docs/models
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "grok-code-fast-1": (PricingInfo.groxPro, ["function-calling"], 256000),
            "grok-4-fast-reasoning": (PricingInfo.groxPro, ["reasoning"], 2000000),
            "grok-4-fast-non-reasoning": (PricingInfo.groxPro, [], 2000000),
            "grok-3": (PricingInfo.groxPro, [], 131072),
            "grok-3-mini": (PricingInfo.groxPro, [], 131072),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "xai",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .fast,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "xai",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Perplexity Fetcher

class PerplexityMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Perplexity pricing from their API docs
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "pplx-pro-online": (PricingInfo.perplexityProOnline, ["vision"], 128000),
            "pplx-70b-online": (PricingInfo.perplexityProOnline, [], 4096),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "perplexity",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .medium,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "perplexity",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - DeepSeek Fetcher

class DeepSeekMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // DeepSeek pricing from their API documentation
        var metadata: [String: ModelMetadata] = [:]
        
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "deepseek-chat": (PricingInfo.deepseekChat, [], 128000),
            "deepseek-coder": (PricingInfo.deepseekChat, ["function-calling"], 128000),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "deepseek",
                pricing: data.pricing,
                maxContextTokens: data.context,
                capabilities: data.capabilities,
                latency: .medium,
                costLevel: getCostLevel(for: data.pricing),
                lastUpdated: Date(),
                source: .providerDocumentation
            )
        }
        
        return metadata
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)
        
        if let metadata = allMetadata[modelId] {
            return metadata
        }
        
        return ModelMetadata(
            modelId: modelId,
            provider: "deepseek",
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
    
    private func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }
}

// MARK: - Local Model Fetcher (Ollama, LMStudio)

class LocalModelMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Local models are self-hosted and free
        return [:]
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        return ModelMetadata.freeSelfHosted(modelId: modelId, provider: "local", context: nil)
    }
}

// MARK: - Generic Fetcher

class GenericMetadataFetcher: ModelMetadataFetcher {
    private let provider: String
    
    init(provider: String) {
        self.provider = provider
    }
    
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Generic fetcher just returns empty metadata for unknown providers
        return [:]
    }
    
    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        return ModelMetadata(
            modelId: modelId,
            provider: provider,
            pricing: nil,
            maxContextTokens: nil,
            capabilities: [],
            latency: nil,
            costLevel: nil,
            lastUpdated: Date(),
            source: .unknown
        )
    }
}

// MARK: - OpenRouter API Response Models

struct OpenRouterResponse: Codable {
    let data: [OpenRouterModel]
}

struct OpenRouterModel: Codable {
    let id: String
    let name: String
    let context_length: Int
    let architecture: OpenRouterArchitecture
    let pricing: OpenRouterPricing
    let supported_parameters: [String]
    let description: String?
}

struct OpenRouterArchitecture: Codable {
    let input_modalities: [String]
    let output_modalities: [String]
}

struct OpenRouterPricing: Codable {
    let prompt: String
    let completion: String
}
