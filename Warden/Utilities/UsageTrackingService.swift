import CoreData
import Foundation
import os

/// Token usage reported by a provider for a single completion.
struct TokenUsage: Codable, Equatable {
    var inputTokens: Int
    var outputTokens: Int
    var cachedInputTokens: Int = 0
    var reasoningTokens: Int = 0

    var isEmpty: Bool { inputTokens <= 0 && outputTokens <= 0 }

    /// Merges two partial reports (e.g. Anthropic splits input/output across events).
    /// Later values win when greater than zero.
    static func merged(_ newer: TokenUsage, into older: TokenUsage?) -> TokenUsage {
        guard let older else { return newer }
        var result = older
        if newer.inputTokens > 0 { result.inputTokens = newer.inputTokens }
        if newer.outputTokens > older.outputTokens { result.outputTokens = newer.outputTokens }
        if newer.cachedInputTokens > 0 { result.cachedInputTokens = newer.cachedInputTokens }
        if newer.reasoningTokens > older.reasoningTokens { result.reasoningTokens = newer.reasoningTokens }
        return result
    }
}

/// Extracts token usage from OpenAI-compatible and Anthropic response payloads.
///
/// Both streaming chunks (`usage` on the final chunk) and non-streaming bodies carry
/// the same top-level shape, so one extractor serves both paths.
enum UsageExtractor {
    /// Extracts usage from an OpenAI-compatible JSON dictionary (`usage.prompt_tokens` / `completion_tokens`).
    static func fromOpenAIDictionary(_ dict: [String: Any]) -> TokenUsage? {
        guard let usage = dict["usage"] as? [String: Any] else { return nil }

        // Responses API style names first, then chat-completions names.
        let input = (usage["input_tokens"] as? NSNumber)?.intValue
            ?? (usage["prompt_tokens"] as? NSNumber)?.intValue ?? 0
        let output = (usage["output_tokens"] as? NSNumber)?.intValue
            ?? (usage["completion_tokens"] as? NSNumber)?.intValue ?? 0

        guard input > 0 || output > 0 else { return nil }

        var result = TokenUsage(inputTokens: input, outputTokens: output)

        if let details = usage["prompt_tokens_details"] as? [String: Any] {
            result.cachedInputTokens = (details["cached_tokens"] as? NSNumber)?.intValue ?? 0
        } else if let details = usage["input_tokens_details"] as? [String: Any] {
            result.cachedInputTokens = (details["cached_tokens"] as? NSNumber)?.intValue ?? 0
        }

        if let details = usage["completion_tokens_details"] as? [String: Any] {
            result.reasoningTokens = (details["reasoning_tokens"] as? NSNumber)?.intValue ?? 0
        } else if let details = usage["output_tokens_details"] as? [String: Any] {
            result.reasoningTokens = (details["reasoning_tokens"] as? NSNumber)?.intValue ?? 0
        }

        return result
    }

    /// Extracts usage from an Anthropic `message_start` / `message_delta` event dictionary
    /// (`message.usage.input_tokens` / `usage.output_tokens`).
    static func fromAnthropicDictionary(_ dict: [String: Any]) -> TokenUsage? {
        let containers: [[String: Any]] = [
            dict["message"] as? [String: Any],
            dict["usage"] as? [String: Any],
        ]
        .compactMap { $0 }

        for container in containers {
            guard let usage = container["usage"] as? [String: Any] else { continue }
            let input = (usage["input_tokens"] as? NSNumber)?.intValue ?? 0
            let output = (usage["output_tokens"] as? NSNumber)?.intValue ?? 0
            guard input > 0 || output > 0 else { continue }

            var result = TokenUsage(inputTokens: input, outputTokens: output)
            result.cachedInputTokens = (usage["cache_read_input_tokens"] as? NSNumber)?.intValue ?? 0
            if let outputDelta = usage["output_tokens"] as? NSNumber,
               let deltaReasoning = usage["reasoning_output_tokens"] as? NSNumber {
                result.reasoningTokens = deltaReasoning.intValue
            }
            return result
        }
        return nil
    }

    /// Extracts usage from an Ollama final chunk (`prompt_eval_count` / `eval_count`).
    static func fromOllamaDictionary(_ dict: [String: Any]) -> TokenUsage? {
        guard let promptEval = dict["prompt_eval_count"] as? NSNumber,
              let eval = dict["eval_count"] as? NSNumber else {
            return nil
        }
        return TokenUsage(inputTokens: promptEval.intValue, outputTokens: eval.intValue)
    }

    /// Provider-agnostic entry point: tries OpenAI-compatible, Anthropic, then Ollama shapes.
    static func extract(from dict: [String: Any]) -> TokenUsage? {
        fromOpenAIDictionary(dict) ?? fromAnthropicDictionary(dict) ?? fromOllamaDictionary(dict)
    }

    /// Extracts usage from raw SSE event data (streaming path).
    static func extract(fromStreamData data: Data?) -> TokenUsage? {
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            return nil
        }
        return extract(from: json)
    }
}

/// Calculates estimated USD cost for token usage using Warden's model metadata pricing.
enum UsageCostCalculator {
    struct CostResult {
        let costUSD: Double
        let source: String
    }

    static func cost(
        for usage: TokenUsage,
        providerName: String,
        modelId: String
    ) -> CostResult {
        let provider = ProviderID(normalizing: providerName)?.rawValue ?? providerName.lowercased()

        guard let metadata = ModelMetadataStorage.getMetadata(provider: provider, modelId: modelId),
              let pricing = metadata.pricing else {
            return CostResult(costUSD: 0, source: "unpriced")
        }

        let inputPerToken = (pricing.inputPer1M ?? 0) / 1_000_000
        let outputPerToken = (pricing.outputPer1M ?? 0) / 1_000_000

        // Cached input is typically billed at a steep discount; use a 50% factor when
        // the provider metadata doesn't distinguish it (conservative middle ground).
        let billableInput = max(0, usage.inputTokens - usage.cachedInputTokens)
        let cachedCost = Double(usage.cachedInputTokens) * inputPerToken * 0.5
        let reasoningCost = Double(usage.reasoningTokens) * outputPerToken

        let cost = Double(billableInput) * inputPerToken
            + cachedCost
            + (Double(usage.outputTokens) * outputPerToken)
            + reasoningCost

        let source: String
        if metadata.isStale {
            source = "cached-stale"
        } else {
            source = pricing.source
        }
        return CostResult(costUSD: cost, source: source)
    }
}

/// Records and aggregates per-completion usage records.
@MainActor
final class UsageTrackingService {
    static let shared = UsageTrackingService()

    private let viewContext: NSManagedObjectContext

    init(viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = viewContext
    }

    /// Records one completion's usage. No-ops when the provider reported no usage.
    func record(
        usage: TokenUsage,
        providerName: String,
        modelId: String,
        chatID: UUID?
    ) {
        guard !usage.isEmpty else { return }

        let cost = UsageCostCalculator.cost(for: usage, providerName: providerName, modelId: modelId)

        let record = UsageRecordEntity(context: viewContext)
        record.id = UUID()
        record.date = Date()
        record.providerName = providerName
        record.modelId = modelId
        record.chatID = chatID
        record.inputTokens = Int64(usage.inputTokens)
        record.outputTokens = Int64(usage.outputTokens)
        record.cachedInputTokens = Int64(usage.cachedInputTokens)
        record.reasoningTokens = Int64(usage.reasoningTokens)
        record.estimatedCostUSD = cost.costUSD
        record.pricingSource = cost.source

        do {
            try viewContext.save()
            #if DEBUG
            WardenLog.app.debug(
                "[Usage] Recorded \(usage.inputTokens, privacy: .public) in / \(usage.outputTokens, privacy: .public) out tokens (~$\(String(format: "%.4f", cost.costUSD), privacy: .public)) for \(modelId, privacy: .public)"
            )
            #endif
        } catch {
            // Never let usage accounting break a chat — log and continue.
            viewContext.rollback()
            WardenLog.app.error(
                "[Usage] Failed to save usage record: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Aggregation

    struct Totals {
        var inputTokens: Int64 = 0
        var outputTokens: Int64 = 0
        var costUSD: Double = 0
        var requestCount: Int = 0
    }

    struct ModelBreakdown: Identifiable {
        let id: String
        let providerName: String
        var totals: Totals
    }

    /// Aggregates records within a date range (nil = all time).
    func totals(from: Date? = nil, to: Date? = nil) -> Totals {
        var result = Totals()
        for record in fetchRecords(from: from, to: to) {
            result.inputTokens += record.inputTokens
            result.outputTokens += record.outputTokens
            result.costUSD += record.estimatedCostUSD
            result.requestCount += 1
        }
        return result
    }

    func breakdownByModel(from: Date? = nil, to: Date? = nil) -> [ModelBreakdown] {
        var grouped: [String: ModelBreakdown] = [:]
        for record in fetchRecords(from: from, to: to) {
            let key = "\(record.providerName ?? "unknown")/\(record.modelId ?? "unknown")"
            var entry = grouped[key] ?? ModelBreakdown(
                id: key,
                providerName: record.providerName ?? "Unknown",
                totals: Totals()
            )
            entry.totals.inputTokens += record.inputTokens
            entry.totals.outputTokens += record.outputTokens
            entry.totals.costUSD += record.estimatedCostUSD
            entry.totals.requestCount += 1
            grouped[key] = entry
        }
        return grouped.values.sorted { $0.totals.costUSD > $1.totals.costUSD }
    }

    /// Daily totals for the trailing `days` days, oldest first (for charts/sparklines).
    func dailyTotals(days: Int) -> [(date: Date, totals: Totals)] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: startOfToday) else {
            return []
        }

        var buckets: [Date: Totals] = [:]
        for offset in 0..<days {
            if let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) {
                buckets[day] = Totals()
            }
        }

        for record in fetchRecords(from: windowStart) {
            guard let date = record.date else { continue }
            let day = calendar.startOfDay(for: date)
            var totals = buckets[day] ?? Totals()
            totals.inputTokens += record.inputTokens
            totals.outputTokens += record.outputTokens
            totals.costUSD += record.estimatedCostUSD
            totals.requestCount += 1
            buckets[day] = totals
        }

        return buckets.keys.sorted().map { ($0, buckets[$0]!) }
    }

    private func fetchRecords(from: Date?, to: Date? = nil) -> [UsageRecordEntity] {
        let request = UsageRecordEntity.fetchRequest()
        var predicates: [NSPredicate] = []
        if let from { predicates.append(NSPredicate(format: "date >= %@", from as NSDate)) }
        if let to { predicates.append(NSPredicate(format: "date <= %@", to as NSDate)) }
        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
        request.fetchBatchSize = 200

        do {
            return try viewContext.fetch(request)
        } catch {
            WardenLog.app.error(
                "[Usage] Failed to fetch usage records: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }
}
