import Foundation
import os

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
        switch ProviderID(normalizing: provider) {
        case .chatgpt:
            return LiteLLMBackedFetcher(provider: "openai")
        case .claude:
            return LiteLLMBackedFetcher(provider: "anthropic")
        case .gemini:
            return LiteLLMBackedFetcher(provider: "gemini")
        case .groq:
            return LiteLLMBackedFetcher(provider: "groq")
        case .openrouter:
            return OpenRouterMetadataFetcher()
        case .mistral:
            return LiteLLMBackedFetcher(provider: "mistral")
        case .xai:
            return LiteLLMBackedFetcher(provider: "xai")
        case .perplexity:
            return LiteLLMBackedFetcher(provider: "perplexity")
        case .deepseek:
            return LiteLLMBackedFetcher(provider: "deepseek")
        case .ollama, .lmstudio:
            return LocalModelMetadataFetcher()
        case nil:
            return GenericMetadataFetcher(provider: provider)
        }
    }
}

// MARK: - LiteLLM-Backed Fetcher

/// Fetches metadata from LiteLLM's community-maintained pricing data.
/// Provides pricing, context windows, and capabilities for major providers.
/// Sendable: All stored properties are immutable or Sendable (actor reference).
final class LiteLLMBackedFetcher: ModelMetadataFetcher, Sendable {
    private let provider: String
    private let liteLLMFetcher = LiteLLMMetadataFetcher()

    init(provider: String) {
        self.provider = provider
    }

    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        return await liteLLMFetcher.fetchMetadata(for: provider)
    }

    func fetchMetadata(for modelId: String, apiKey: String) async throws -> ModelMetadata {
        let allMetadata = try await fetchAllMetadata(apiKey: apiKey)

        if let metadata = allMetadata[modelId] {
            return metadata
        }

        // Deterministic fuzzy match:
        // 1) exact (case-insensitive)
        // 2) separator-suffix versions (e.g. "gpt-5" -> "gpt-5-0125")
        // 3) longest-prefix match
        let normalizedId = modelId.lowercased()
        let sortedKeys = allMetadata.keys.sorted { $0.lowercased() < $1.lowercased() }

        if let exactKey = sortedKeys.first(where: { $0.lowercased() == normalizedId }) {
            return allMetadata[exactKey]!
        }

        let separatorSuffixes = ["-", "_", "/"].map { normalizedId + $0 }
        if let versionKey = sortedKeys
            .filter({ key in separatorSuffixes.contains(where: { key.lowercased().hasPrefix($0) }) })
            .min(by: { $0.count < $1.count })
        {
            return allMetadata[versionKey]!
        }

        if let bestPrefixKey = sortedKeys
            .filter({ normalizedId.hasPrefix($0.lowercased()) })
            .max(by: { $0.count < $1.count })
        {
            return allMetadata[bestPrefixKey]!
        }

        if let bestExpansionKey = sortedKeys
            .filter({ $0.lowercased().hasPrefix(normalizedId) })
            .min(by: { $0.count < $1.count })
        {
            return allMetadata[bestExpansionKey]!
        }

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







// MARK: - Groq Fetcher

class GroqMetadataFetcher: ModelMetadataFetcher {
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // Groq metadata fetching via API is not implemented.
        return [:]
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
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func fetchAllMetadata(apiKey: String) async throws -> [String: ModelMetadata] {
        // OpenRouter exposes all models with pricing via public API
        guard let url = URL(string: baseURL) else {
            throw NSError(domain: "OpenRouterFetcher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let (data, response) = try await session.data(for: request)
        
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
                supportedParameters: model.supported_parameters,
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
        
        // Parse vision from input modalities
        if model.architecture.input_modalities.contains("image") {
            capabilities.append("vision")
        }
        
        // Parse reasoning from supported parameters
        if model.supported_parameters.contains("reasoning") {
            capabilities.append("reasoning")
        }
        
        // Parse function calling from supported parameters
        if model.supported_parameters.contains("tools") {
            capabilities.append("function-calling")
        }
        
        // Debug logging to verify capability parsing
        if !capabilities.isEmpty {
            #if DEBUG
            WardenLog.app.debug(
                "OpenRouter model \(model.id, privacy: .public) capabilities: \(capabilities.joined(separator: ", "), privacy: .public)"
            )
            #endif
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
