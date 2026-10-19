import Foundation

/// Extracts provider token usage from response bodies and streaming events.
///
/// Supported shapes:
/// - OpenAI-compatible `usage` (`prompt_tokens`, `completion_tokens`, `*_details`), including the
///   trailing stream chunk with empty `choices` and Groq's `x_groq.usage`
/// - OpenAI Responses API `response.completed` events (`response.usage`) and bodies (`usage.input_tokens`)
/// - Anthropic `message_start` (`message.usage`), `message_delta` (`usage.output_tokens`) and message bodies
/// - Ollama `prompt_eval_count` / `eval_count` on the final chunk
/// - Gemini native `usageMetadata`
enum UsageExtractor {
    private static let markers: [Data] = ["usage", "eval_count"].map { Data($0.utf8) }
    private static let nullUsageMarker = Data("\"usage\":null".utf8)
    private static let objectUsageMarkers: [Data] = ["\"usage\":{", "\"usage\": {", "usageMetadata", "eval_count"]
        .map { Data($0.utf8) }

    /// Parses usage from one SSE/NDJSON event payload or a full JSON response body.
    static func usage(from data: Data) -> TokenUsage? {
        guard markers.contains(where: { data.range(of: $0) != nil }) else { return nil }
        // OpenAI-compatible streams with `include_usage` send `"usage":null` on every content chunk.
        if data.range(of: nullUsageMarker) != nil,
           !objectUsageMarkers.contains(where: { data.range(of: $0) != nil }) {
            return nil
        }
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return usage(fromJSON: json)
    }

    static func usage(fromJSON json: [String: Any]) -> TokenUsage? {
        if let message = json["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any],
           let parsed = parseUsageDictionary(usage) {
            return parsed
        }

        if let response = json["response"] as? [String: Any],
           let usage = response["usage"] as? [String: Any],
           let parsed = parseUsageDictionary(usage) {
            return parsed
        }

        if let usage = json["usage"] as? [String: Any], let parsed = parseUsageDictionary(usage) {
            return parsed
        }

        if let groq = json["x_groq"] as? [String: Any],
           let usage = groq["usage"] as? [String: Any],
           let parsed = parseUsageDictionary(usage) {
            return parsed
        }

        if let metadata = json["usageMetadata"] as? [String: Any], let parsed = parseGeminiUsage(metadata) {
            return parsed
        }

        if json["prompt_eval_count"] != nil || json["eval_count"] != nil {
            let input = intValue(json["prompt_eval_count"]) ?? 0
            let output = intValue(json["eval_count"]) ?? 0
            guard input > 0 || output > 0 else { return nil }
            return TokenUsage(inputTokens: input, outputTokens: output)
        }

        return nil
    }

    private static func parseUsageDictionary(_ usage: [String: Any]) -> TokenUsage? {
        if usage["prompt_tokens"] != nil || usage["completion_tokens"] != nil {
            let input = intValue(usage["prompt_tokens"]) ?? 0
            let output = intValue(usage["completion_tokens"]) ?? 0
            let promptDetails = usage["prompt_tokens_details"] as? [String: Any]
            let completionDetails = usage["completion_tokens_details"] as? [String: Any]
            let cached = intValue(promptDetails?["cached_tokens"]) ?? intValue(usage["prompt_cache_hit_tokens"])
            let reasoning = intValue(completionDetails?["reasoning_tokens"])
            return TokenUsage(
                inputTokens: input,
                outputTokens: output,
                cachedInputTokens: positiveOrNil(cached),
                reasoningTokens: positiveOrNil(reasoning)
            )
        }

        guard usage["input_tokens"] != nil || usage["output_tokens"] != nil else { return nil }

        let input = intValue(usage["input_tokens"]) ?? 0
        let output = intValue(usage["output_tokens"]) ?? 0

        // Anthropic reports cache reads/writes separately from `input_tokens`;
        // the Responses API includes cached tokens in `input_tokens` and lists them under details.
        let cacheRead = intValue(usage["cache_read_input_tokens"])
        let cacheWrite = intValue(usage["cache_creation_input_tokens"])
        if cacheRead != nil || cacheWrite != nil {
            return TokenUsage(
                inputTokens: input + (cacheRead ?? 0) + (cacheWrite ?? 0),
                outputTokens: output,
                cachedInputTokens: positiveOrNil(cacheRead),
                reasoningTokens: nil
            )
        }

        let inputDetails = usage["input_tokens_details"] as? [String: Any]
        let outputDetails = usage["output_tokens_details"] as? [String: Any]
        return TokenUsage(
            inputTokens: input,
            outputTokens: output,
            cachedInputTokens: positiveOrNil(intValue(inputDetails?["cached_tokens"])),
            reasoningTokens: positiveOrNil(intValue(outputDetails?["reasoning_tokens"]))
        )
    }

    private static func parseGeminiUsage(_ metadata: [String: Any]) -> TokenUsage? {
        guard metadata["promptTokenCount"] != nil || metadata["candidatesTokenCount"] != nil else { return nil }
        let input = intValue(metadata["promptTokenCount"]) ?? 0
        let candidates = intValue(metadata["candidatesTokenCount"]) ?? 0
        let thoughts = intValue(metadata["thoughtsTokenCount"])
        // Gemini reports thinking tokens separately from candidates, unlike OpenAI/Anthropic.
        return TokenUsage(
            inputTokens: input,
            outputTokens: candidates + (thoughts ?? 0),
            cachedInputTokens: positiveOrNil(intValue(metadata["cachedContentTokenCount"])),
            reasoningTokens: positiveOrNil(thoughts)
        )
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let int as Int: return int
        case let number as NSNumber: return number.intValue
        case let double as Double: return Int(double)
        case let string as String: return Int(string)
        default: return nil
        }
    }

    private static func positiveOrNil(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }
}
