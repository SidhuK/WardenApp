import Foundation

/// Highlights shown on multi-model compare columns.
enum CompareBadge: Hashable, CaseIterable {
    case fastest
    case cheapest

    var title: String {
        switch self {
        case .fastest: return "Fastest"
        case .cheapest: return "Cheapest"
        }
    }

    var systemImage: String {
        switch self {
        case .fastest: return "bolt.fill"
        case .cheapest: return "dollarsign.circle.fill"
        }
    }
}

/// The subset of a compare column's state that badge selection depends on.
struct CompareCandidate: Equatable {
    let id: UUID
    /// Finished without an error and produced output.
    let isSuccessful: Bool
    let totalDuration: TimeInterval?
    let costUSD: Double?
}

enum CompareStats {
    /// Assigns badges once at least two columns finished successfully.
    ///
    /// Every candidate tied for the best value gets the badge, unless all of them tie, in which case the
    /// badge would not distinguish anything and is omitted. A badge also needs at least two successful
    /// candidates with a known value for that metric.
    static func badges(for candidates: [CompareCandidate]) -> [UUID: Set<CompareBadge>] {
        let successful = candidates.filter(\.isSuccessful)
        guard successful.count >= 2 else { return [:] }

        var result: [UUID: Set<CompareBadge>] = [:]
        for id in winners(successful, value: \.totalDuration) {
            result[id, default: []].insert(.fastest)
        }
        for id in winners(successful, value: \.costUSD) {
            result[id, default: []].insert(.cheapest)
        }
        return result
    }

    private static func winners(
        _ candidates: [CompareCandidate],
        value: KeyPath<CompareCandidate, Double?>
    ) -> [UUID] {
        let known = candidates.compactMap { candidate in
            candidate[keyPath: value].map { (id: candidate.id, value: $0) }
        }
        guard known.count >= 2, let best = known.map(\.value).min() else { return [] }
        let tied = known.filter { $0.value == best }
        guard tied.count < known.count else { return [] }
        return tied.map(\.id)
    }

    /// "0.8s" below a minute, "1m 05s" above.
    static func formatDuration(_ interval: TimeInterval) -> String {
        let interval = max(0, interval)
        if interval < 60 {
            return String(format: "%.1fs", interval)
        }
        let totalSeconds = Int(interval.rounded())
        return String(format: "%dm %02ds", totalSeconds / 60, totalSeconds % 60)
    }

    /// Four decimals below a dollar so typical per-response costs stay readable.
    static func formatCost(_ cost: Double) -> String {
        if cost <= 0 {
            return "$0.00"
        }
        if cost < 0.0001 {
            return "<$0.0001"
        }
        if cost < 1 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.2f", cost)
    }

    static func formatTokens(_ usage: TokenUsage) -> String {
        var parts = [
            "\(usage.inputTokens.formatted()) input tokens",
            "\(usage.outputTokens.formatted()) output tokens",
        ]
        if let cached = usage.cachedInputTokens, cached > 0 {
            parts.append("\(cached.formatted()) cached")
        }
        if let reasoning = usage.reasoningTokens, reasoning > 0 {
            parts.append("\(reasoning.formatted()) reasoning")
        }
        return parts.joined(separator: ", ")
    }
}
