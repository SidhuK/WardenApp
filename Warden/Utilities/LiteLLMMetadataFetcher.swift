import Foundation
import os

/// Fetches model metadata from LiteLLM's community-maintained pricing JSON.
/// This provides pricing data for OpenAI, Anthropic, and other providers without manual maintenance.
/// Falls back to cached data if fetch fails, with graceful degradation if parsing changes.
///
/// Thread-safe: Uses actor isolation for cache access, URLSession is Sendable.
actor LiteLLMMetadataFetcher {
    private let jsonURL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
    private let session: URLSession
    private let cacheKey = "litellm_model_prices_cache"
    private let cacheTimestampKey = "litellm_model_prices_timestamp"
    private let cacheDuration: TimeInterval = 60 * 60 * 24 // 24 hours

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Fetch metadata for a specific provider (e.g., "openai", "anthropic")
    func fetchMetadata(for provider: String) async -> [String: ModelMetadata] {
        // Try to fetch fresh data
        if let freshData = await fetchFromRemote() {
            if let parsed = Self.parseModels(from: freshData, provider: provider) {
                cacheData(freshData)
                return parsed
            }
        }

        // Fall back to cached data
        if let cachedData = loadCachedData() {
            if let parsed = Self.parseModels(from: cachedData, provider: provider) {
                #if DEBUG
                WardenLog.app.debug("LiteLLM: Using cached data for \(provider, privacy: .public)")
                #endif
                return parsed
            }
        }

        // Complete fallback: empty metadata
        #if DEBUG
        WardenLog.app.warning("LiteLLM: No metadata available for \(provider, privacy: .public)")
        #endif
        return [:]
    }

    // MARK: - Remote Fetch

    nonisolated private func fetchFromRemote() async -> Data? {
        guard let url = URL(string: jsonURL) else { return nil }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                #if DEBUG
                WardenLog.app.warning("LiteLLM: HTTP error fetching pricing data")
                #endif
                return nil
            }
            return data
        } catch {
            #if DEBUG
            WardenLog.app.warning("LiteLLM: Fetch failed: \(error.localizedDescription, privacy: .public)")
            #endif
            return nil
        }
    }

    // MARK: - Parsing (Defensive, Pure Function)

    /// Pure function - no state access, safe to call from any context
    nonisolated private static func parseModels(from data: Data, provider: String) -> [String: ModelMetadata]? {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return nil
            }

            var result: [String: ModelMetadata] = [:]
            let providerLower = provider.lowercased()

            for (modelId, value) in json {
                // Skip non-model entries like "sample_spec"
                guard let modelInfo = value as? [String: Any] else { continue }

                // Filter by provider
                guard let litellmProvider = modelInfo["litellm_provider"] as? String,
                      matchesProvider(litellmProvider, target: providerLower) else {
                    continue
                }

                // Parse pricing (per-token to per-1M conversion)
                let inputCostPerToken = modelInfo["input_cost_per_token"] as? Double
                let outputCostPerToken = modelInfo["output_cost_per_token"] as? Double

                let inputPer1M = inputCostPerToken.map { $0 * 1_000_000 }
                let outputPer1M = outputCostPerToken.map { $0 * 1_000_000 }

                let pricing: PricingInfo? = (inputPer1M != nil || outputPer1M != nil)
                    ? PricingInfo(inputPer1M: inputPer1M, outputPer1M: outputPer1M, source: "litellm")
                    : nil

                // Parse context window
                let maxInputTokens = modelInfo["max_input_tokens"] as? Int
                let maxTokens = modelInfo["max_tokens"] as? Int
                let contextWindow = maxInputTokens ?? maxTokens

                // Parse capabilities
                var capabilities: [String] = []
                if modelInfo["supports_vision"] as? Bool == true {
                    capabilities.append("vision")
                }
                if modelInfo["supports_function_calling"] as? Bool == true {
                    capabilities.append("function-calling")
                }
                if modelInfo["supports_response_schema"] as? Bool == true {
                    capabilities.append("structured-output")
                }
                // Check for reasoning models
                if modelInfo["supports_reasoning"] as? Bool == true {
                    capabilities.append("reasoning")
                } else {
                    // Fallback heuristic for older LiteLLM data without explicit flags.
                    let id = modelId.lowercased()
                    if id.hasPrefix("o1") || id.hasPrefix("o3") || id.hasPrefix("o4") ||
                        id.contains("-thinking") || id.contains("_thinking") || id.contains("/thinking") ||
                        id.contains("-reasoning") || id.contains("_reasoning") || id.contains("/reasoning")
                    {
                        capabilities.append("reasoning")
                    }
                }

                // Build metadata
                let metadata = ModelMetadata(
                    modelId: cleanModelId(modelId),
                    provider: provider,
                    pricing: pricing,
                    maxContextTokens: contextWindow,
                    capabilities: capabilities,
                    latency: estimateLatency(for: modelId),
                    costLevel: pricing.flatMap { getCostLevel(for: $0) },
                    lastUpdated: Date(),
                    source: .providerDocumentation
                )

                result[metadata.modelId] = metadata
            }

            #if DEBUG
            WardenLog.app.debug("LiteLLM: Parsed \(result.count, privacy: .public) models for \(provider, privacy: .public)")
            #endif

            return result.isEmpty ? nil : result

        } catch {
            #if DEBUG
            WardenLog.app.warning("LiteLLM: Parse error: \(error.localizedDescription, privacy: .public)")
            #endif
            return nil
        }
    }

    /// Match provider names (handles variations like "openai", "azure", "anthropic")
    nonisolated private static func matchesProvider(_ litellmProvider: String, target: String) -> Bool {
        let lp = litellmProvider.lowercased()

        switch target {
        case "openai", "chatgpt":
            return lp == "openai" || lp == "openai_compatible"
        case "anthropic", "claude":
            return lp == "anthropic"
        case "gemini", "google":
            return lp == "gemini" || lp == "vertex_ai" || lp == "vertex_ai_beta"
        case "mistral":
            return lp == "mistral"
        case "deepseek":
            return lp == "deepseek"
        case "xai":
            return lp == "xai"
        case "perplexity":
            return lp == "perplexity"
        case "groq":
            return lp == "groq"
        default:
            return lp == target
        }
    }

    /// Clean model ID (remove provider prefix if present)
    nonisolated private static func cleanModelId(_ modelId: String) -> String {
        // LiteLLM uses format like "openai/gpt-5" or just "gpt-5"
        if modelId.contains("/") {
            return String(modelId.split(separator: "/").last ?? Substring(modelId))
        }
        return modelId
    }

    nonisolated private static func estimateLatency(for modelId: String) -> LatencyLevel {
        let id = modelId.lowercased()
        if id.contains("mini") || id.contains("nano") || id.contains("haiku") || id.contains("flash") {
            return .fast
        } else if id.contains("opus") || id.contains("pro") || id.contains("large") {
            return .slow
        }
        return .medium
    }

    nonisolated private static func getCostLevel(for pricing: PricingInfo) -> CostLevel? {
        guard let inputCost = pricing.inputPer1M else { return nil }
        if inputCost < 1.0 {
            return .cheap
        } else if inputCost < 10.0 {
            return .standard
        } else {
            return .expensive
        }
    }

    // MARK: - Caching (Actor-isolated)

    private func cacheData(_ data: Data) {
        UserDefaults.standard.set(data, forKey: cacheKey)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: cacheTimestampKey)
    }

    private func loadCachedData() -> Data? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey) else { return nil }

        // Check if cache is still valid
        let timestamp = UserDefaults.standard.double(forKey: cacheTimestampKey)
        guard timestamp > 0 else {
            #if DEBUG
            WardenLog.app.debug("LiteLLM: Cache timestamp missing; treating cache as expired")
            #endif
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
            return nil
        }

        let age = Date().timeIntervalSince1970 - timestamp
        if age > cacheDuration * 7 { // Allow stale cache up to 7 days for fallback
            #if DEBUG
            WardenLog.app.debug("LiteLLM: Cache too old; treating as expired")
            #endif
            UserDefaults.standard.removeObject(forKey: cacheKey)
            UserDefaults.standard.removeObject(forKey: cacheTimestampKey)
            return nil
        } else if age > cacheDuration {
            #if DEBUG
            WardenLog.app.debug("LiteLLM: Cache is stale but using as fallback")
            #endif
        }

        return data
    }
}
