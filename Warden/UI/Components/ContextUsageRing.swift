import CoreData
import SwiftUI

/// Rough context-window accounting for the composer's context ring.
enum ContextUsageEstimator {
    struct MessageSample: Equatable {
        var characterCount: Int
        var isAssistant: Bool
        var usage: TokenUsage?
    }

    enum Level: Equatable {
        case normal
        case warning
        case critical
    }

    static let charactersPerToken = 4

    static func estimatedTokens(forCharacterCount count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (count + charactersPerToken - 1) / charactersPerToken
    }

    /// Tokens the next request is expected to use.
    ///
    /// When the latest assistant reply reported usage, its input + output tokens already cover everything up to
    /// and including that reply, so only later messages are estimated from their length. Otherwise every message
    /// (and the system prompt) is estimated at ~4 characters per token. The composer text is always added.
    static func estimatedTokens(
        messages: [MessageSample],
        systemPromptCharacters: Int = 0,
        composerCharacters: Int
    ) -> Int {
        let composerTokens = estimatedTokens(forCharacterCount: composerCharacters)

        if let anchorIndex = messages.lastIndex(where: { $0.isAssistant && $0.usage != nil }),
           let usage = messages[anchorIndex].usage {
            let laterTokens = messages[(anchorIndex + 1)...]
                .reduce(0) { $0 + estimatedTokens(forCharacterCount: $1.characterCount) }
            return usage.inputTokens + usage.outputTokens + laterTokens + composerTokens
        }

        let messageTokens = messages.reduce(0) { $0 + estimatedTokens(forCharacterCount: $1.characterCount) }
        return estimatedTokens(forCharacterCount: systemPromptCharacters) + messageTokens + composerTokens
    }

    /// Fraction of the window in use, or nil when the window size is unknown.
    static func fraction(used: Int, maxTokens: Int?) -> Double? {
        guard let maxTokens, maxTokens > 0 else { return nil }
        return Double(max(used, 0)) / Double(maxTokens)
    }

    static func level(for fraction: Double) -> Level {
        if fraction > 0.9 { return .critical }
        if fraction >= 0.7 { return .warning }
        return .normal
    }

    /// Compact token count: `950`, `12.4k`, `200k`, `1M`, `1.5M`.
    static func formattedTokenCount(_ count: Int) -> String {
        func compact(_ value: Double, suffix: String) -> String {
            let rounded = (value * 10).rounded() / 10
            if rounded == rounded.rounded() {
                return "\(Int(rounded))\(suffix)"
            }
            return String(format: "%.1f%@", rounded, suffix)
        }

        if count >= 1_000_000 { return compact(Double(count) / 1_000_000, suffix: "M") }
        if count >= 1_000 {
            let thousands = Double(count) / 1_000
            // 999,950+ would round up to "1000k".
            if (thousands * 10).rounded() / 10 >= 1_000 { return compact(Double(count) / 1_000_000, suffix: "M") }
            return compact(thousands, suffix: "k")
        }
        return "\(max(count, 0))"
    }

    /// e.g. "~12.4k of 200k tokens (6%)".
    static func tooltip(used: Int, maxTokens: Int) -> String {
        let percent = maxTokens > 0 ? Int((Double(used) / Double(maxTokens) * 100).rounded()) : 0
        return "~\(formattedTokenCount(used)) of \(formattedTokenCount(maxTokens)) tokens (\(percent)%)"
    }
}

/// Small ring next to the model picker showing roughly how full the model's context window is.
struct ContextUsageRing: View {
    @ObservedObject var chat: ChatEntity
    var composerText: String
    @ObservedObject private var metadataCache = ModelMetadataCache.shared

    private var maxTokens: Int? {
        guard let providerType = chat.apiService?.type, !chat.gptModel.isEmpty else { return nil }
        return metadataCache.getMetadata(provider: providerType.lowercased(), modelId: chat.gptModel)?.maxContextTokens
    }

    /// Identifies the chat history the cached estimate was computed for.
    private struct HistoryKey: Equatable {
        var chatID: NSManagedObjectID
        var messageCount: Int
        var lastMessageID: NSManagedObjectID?
        var lastMessageLength: Int
        var lastMessageHasUsage: Bool
        var systemPromptLength: Int
    }

    @State private var cachedHistory: (key: HistoryKey, tokens: Int)?

    private var historyKey: HistoryKey {
        let last = chat.lastMessage
        return HistoryKey(
            chatID: chat.objectID,
            messageCount: chat.messages.count,
            lastMessageID: last?.objectID,
            lastMessageLength: last?.body.utf16.count ?? 0,
            lastMessageHasUsage: last?.metricsJson != nil,
            systemPromptLength: chat.systemMessage.utf16.count
        )
    }

    private func historyTokens(for key: HistoryKey) -> Int {
        if let cachedHistory, cachedHistory.key == key {
            return cachedHistory.tokens
        }
        let samples = chat.messagesArray.map { message in
            ContextUsageEstimator.MessageSample(
                // UTF-16 length is O(1) for bridged strings and close enough for a ~4 chars/token estimate.
                characterCount: message.body.utf16.count,
                isAssistant: !message.own,
                usage: message.own ? nil : message.metrics?.usage
            )
        }
        // The composer estimate is purely additive, so history can be computed once and reused per keystroke.
        return ContextUsageEstimator.estimatedTokens(
            messages: samples,
            systemPromptCharacters: key.systemPromptLength,
            composerCharacters: 0
        )
    }

    var body: some View {
        let key = historyKey
        ring(historyKey: key)
            .onAppear { cacheHistory(for: key) }
            .onChange(of: key) { _, newKey in cacheHistory(for: newKey) }
    }

    private func cacheHistory(for key: HistoryKey) {
        guard cachedHistory?.key != key else { return }
        cachedHistory = (key, historyTokens(for: key))
    }

    @ViewBuilder
    private func ring(historyKey key: HistoryKey) -> some View {
        if let maxTokens {
            let used = historyTokens(for: key)
                + ContextUsageEstimator.estimatedTokens(forCharacterCount: composerText.utf16.count)
            if let fraction = ContextUsageEstimator.fraction(used: used, maxTokens: maxTokens) {
                ringView(used: used, maxTokens: maxTokens, fraction: fraction)
            }
        }
    }

    private func ringView(used: Int, maxTokens: Int, fraction: Double) -> some View {
        Group {
            let color = Self.color(for: ContextUsageEstimator.level(for: fraction))
            let tooltip = ContextUsageEstimator.tooltip(used: used, maxTokens: maxTokens)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0.02), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 14, height: 14)
            .padding(2)
            .contentShape(Rectangle())
            .help(tooltip)
            .accessibilityElement()
            .accessibilityLabel("Context usage")
            .accessibilityValue(tooltip)
        }
    }

    private static func color(for level: ContextUsageEstimator.Level) -> Color {
        switch level {
        case .normal: return .secondary
        case .warning: return .orange
        case .critical: return .red
        }
    }
}
