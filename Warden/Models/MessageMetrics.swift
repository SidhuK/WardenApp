import Foundation

/// Token counts reported by a provider for a single response.
///
/// `inputTokens` always includes cached input tokens, and `outputTokens` always includes
/// reasoning tokens, so `totalTokens` never double counts.
public struct TokenUsage: Codable, Equatable, Sendable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cachedInputTokens: Int?
    public var reasoningTokens: Int?

    public init(inputTokens: Int, outputTokens: Int, cachedInputTokens: Int? = nil, reasoningTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedInputTokens = cachedInputTokens
        self.reasoningTokens = reasoningTokens
    }

    public var totalTokens: Int { inputTokens + outputTokens }

    /// Combines two usage snapshots from the same response.
    ///
    /// Providers report cumulative counts (Anthropic sends input in `message_start` and the running
    /// output total in `message_delta`), so each field keeps the larger value instead of summing.
    public func merged(with other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: max(inputTokens, other.inputTokens),
            outputTokens: max(outputTokens, other.outputTokens),
            cachedInputTokens: Self.maxOptional(cachedInputTokens, other.cachedInputTokens),
            reasoningTokens: Self.maxOptional(reasoningTokens, other.reasoningTokens)
        )
    }

    /// Sums usage from separate requests (for example a tool-call round trip and its follow-up).
    public func adding(_ other: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: inputTokens + other.inputTokens,
            outputTokens: outputTokens + other.outputTokens,
            cachedInputTokens: Self.sumOptional(cachedInputTokens, other.cachedInputTokens),
            reasoningTokens: Self.sumOptional(reasoningTokens, other.reasoningTokens)
        )
    }

    private static func maxOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        switch (lhs, rhs) {
        case let (l?, r?): return max(l, r)
        case let (l?, nil): return l
        case let (nil, r?): return r
        case (nil, nil): return nil
        }
    }

    private static func sumOptional(_ lhs: Int?, _ rhs: Int?) -> Int? {
        if lhs == nil && rhs == nil { return nil }
        return (lhs ?? 0) + (rhs ?? 0)
    }
}

extension Optional where Wrapped == TokenUsage {
    func adding(_ other: TokenUsage?) -> TokenUsage? {
        switch (self, other) {
        case let (lhs?, rhs?): return lhs.adding(rhs)
        case let (lhs?, nil): return lhs
        case let (nil, rhs?): return rhs
        case (nil, nil): return nil
        }
    }
}

/// Per-message response metrics persisted as JSON in `MessageEntity.metricsJson`.
public struct MessageMetrics: Codable, Equatable, Sendable {
    public var providerType: String?
    public var providerName: String?
    public var modelId: String?
    public var usage: TokenUsage?
    public var costUSD: Double?
    public var requestStart: Date?
    public var firstTokenAt: Date?
    public var finishedAt: Date?
    public var reasoningStart: Date?
    public var reasoningEnd: Date?

    public init(
        providerType: String? = nil,
        providerName: String? = nil,
        modelId: String? = nil,
        usage: TokenUsage? = nil,
        costUSD: Double? = nil,
        requestStart: Date? = nil,
        firstTokenAt: Date? = nil,
        finishedAt: Date? = nil,
        reasoningStart: Date? = nil,
        reasoningEnd: Date? = nil
    ) {
        self.providerType = providerType
        self.providerName = providerName
        self.modelId = modelId
        self.usage = usage
        self.costUSD = costUSD
        self.requestStart = requestStart
        self.firstTokenAt = firstTokenAt
        self.finishedAt = finishedAt
        self.reasoningStart = reasoningStart
        self.reasoningEnd = reasoningEnd
    }

    public var timeToFirstToken: TimeInterval? {
        Self.interval(from: requestStart, to: firstTokenAt)
    }

    public var totalDuration: TimeInterval? {
        Self.interval(from: requestStart, to: finishedAt)
    }

    public var reasoningDuration: TimeInterval? {
        Self.interval(from: reasoningStart, to: reasoningEnd)
    }

    private static func interval(from start: Date?, to end: Date?) -> TimeInterval? {
        guard let start, let end else { return nil }
        return max(0, end.timeIntervalSince(start))
    }

    static let jsonEncoder = JSONEncoder()
    static let jsonDecoder = JSONDecoder()
}

enum UsageCostCalculator {
    typealias PricingLookup = (_ provider: String, _ modelId: String) -> PricingInfo?

    static let defaultPricingLookup: PricingLookup = { provider, modelId in
        ModelMetadataStorage.getMetadata(provider: provider, modelId: modelId)?.pricing
    }

    /// Estimated cost in USD, or nil when pricing for the model is unknown.
    static func cost(
        for usage: TokenUsage,
        providerType: String,
        modelId: String,
        pricingLookup: PricingLookup = defaultPricingLookup
    ) -> Double? {
        guard let pricing = pricingLookup(providerType.lowercased(), modelId) else { return nil }
        return cost(for: usage, pricing: pricing)
    }

    static func cost(for usage: TokenUsage, pricing: PricingInfo) -> Double? {
        // Cached input is billed at the full input rate because PricingInfo carries no cached rate,
        // so this can overestimate for providers that discount cache hits.
        // Reasoning tokens are already part of outputTokens and are not billed again.
        var total = 0.0
        if usage.inputTokens > 0 {
            guard let inputRate = pricing.inputPer1M else { return nil }
            total += Double(usage.inputTokens) * inputRate / 1_000_000
        }
        if usage.outputTokens > 0 {
            guard let outputRate = pricing.outputPer1M else { return nil }
            total += Double(usage.outputTokens) * outputRate / 1_000_000
        }
        if pricing.inputPer1M == nil && pricing.outputPer1M == nil {
            return nil
        }
        return total
    }
}
