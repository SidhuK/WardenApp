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
        default:
            return GenericMetadataFetcher(provider: provider)
        }
    }
}

// MARK: - OpenAI Fetcher

class OpenAIMetadataFetcher: ModelMetadataFetcher {
    private let baseURL = URL(string: "https://api.openai.com/v1")!
    
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // For now, use hardcoded pricing since OpenAI doesn't expose it via API
        // This can be enhanced to scrape from openai.com/pricing if needed
        var metadata: [String: ModelMetadata] = [:]
        
        // Common OpenAI models with pricing
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
        var metadata: [String: ModelMetadata] = [:]
        
        // Common Anthropic models with pricing
        let models: [String: (pricing: PricingInfo, capabilities: [String], context: Int?)] = [
            "claude-3-opus-20240229": (PricingInfo.claudeOpus, ["vision"], 200000),
            "claude-3-sonnet-20240229": (PricingInfo.claudeSonnet, ["vision"], 200000),
            "claude-3-haiku-20240307": (PricingInfo.claudeHaiku, ["vision"], 200000),
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
        var metadata: [String: ModelMetadata] = [:]
        
        // Common Gemini models
        let models: [String: (pricing: PricingInfo?, capabilities: [String], context: Int?)] = [
            "gemini-pro-vision": (nil, ["vision"], 32000),
            "gemini-pro": (nil, [], 32000),
            "gemini-2.0-flash": (nil, ["vision"], 1000000),
        ]
        
        for (modelId, data) in models {
            metadata[modelId] = ModelMetadata(
                modelId: modelId,
                provider: "gemini",
                pricing: data.0,
                maxContextTokens: data.context,
                capabilities: data.1,
                latency: .fast,
                costLevel: nil,
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
}

// MARK: - Groq Fetcher

class GroqMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        var metadata: [String: ModelMetadata] = [:]
        
        // Groq models are typically free
        let models: [String: (capabilities: [String], context: Int?)] = [
            "mixtral-8x7b-32768": ([], 32768),
            "llama2-70b-4096": ([], 4096),
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
