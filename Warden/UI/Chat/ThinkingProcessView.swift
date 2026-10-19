import SwiftUI

/// Identifies the message a reasoning block belongs to, so its timing and expansion state survive view
/// recycling in the lazy message list. A `nil` message ID denotes the response currently streaming in a chat.
struct ReasoningKey: Hashable {
    let chatID: UUID
    let messageID: Int64?

    static func live(chatID: UUID) -> ReasoningKey {
        ReasoningKey(chatID: chatID, messageID: nil)
    }
}

/// Session-only record of how long each response spent reasoning, plus per-message expand/collapse state.
/// Nothing here is persisted; saved messages carry their own reasoning duration in `MessageEntity.metrics`.
@MainActor
final class ReasoningTimingStore: ObservableObject {
    static let shared = ReasoningTimingStore()

    struct Timing: Equatable {
        let start: Date
        var end: Date?

        var duration: TimeInterval? {
            end.map { $0.timeIntervalSince(start) }
        }
    }

    @Published private var timings: [ReasoningKey: Timing] = [:]
    @Published private var expansion: [ReasoningKey: Bool] = [:]
    /// UTF-8 length of the live stream already searched for the closing tag, per chat. Not published.
    private var closeTagScanOffsets: [UUID: Int] = [:]

    private static let openTag = "<think>"
    private static let closeTag = "</think>"
    /// Reasoning always opens a response, so only the head of the stream is checked for the opening tag.
    private static let openTagSearchWindow = 256

    func timing(for key: ReasoningKey) -> Timing? {
        timings[key]
    }

    /// Reasoning timing of the response currently streaming in `chatID`, if it has started reasoning.
    func liveTiming(chatID: UUID) -> Timing? {
        timings[ReasoningKey.live(chatID: chatID)]
    }

    func isExpanded(_ key: ReasoningKey) -> Bool? {
        expansion[key]
    }

    func setExpanded(_ expanded: Bool, for key: ReasoningKey) {
        expansion[key] = expanded
    }

    /// Stream currently owning each chat's live state. A cancelled stream can finish after its replacement began.
    private var activeStreams: [UUID: UUID] = [:]

    /// Clears any leftover live state before a new response starts streaming in the chat. Returns a token that
    /// `finishStream` must present, so a superseded stream cannot finish its replacement's state.
    func beginStream(chatID: UUID) -> UUID {
        let token = UUID()
        activeStreams[chatID] = token
        closeTagScanOffsets[chatID] = nil
        let key = ReasoningKey.live(chatID: chatID)
        if timings[key] != nil {
            timings[key] = nil
        }
        if expansion[key] != nil {
            expansion[key] = nil
        }
        return token
    }

    /// Records the first reasoning token and the first answer token as the accumulated stream text grows.
    func streamDidUpdate(chatID: UUID, text: String) {
        let key = ReasoningKey.live(chatID: chatID)
        if let timing = timings[key] {
            guard timing.end == nil, streamContainsCloseTag(chatID: chatID, text: text) else { return }
            timings[key]?.end = Date()
        }
        else if text.prefix(Self.openTagSearchWindow).contains(Self.openTag) {
            let now = Date()
            timings[key] = Timing(start: now, end: streamContainsCloseTag(chatID: chatID, text: text) ? now : nil)
        }
    }

    /// Searches only the text appended since the last call, backing up by one tag length so a closing tag
    /// split across chunks is still found. Falls back to a full scan if the text shrank.
    private func streamContainsCloseTag(chatID: UUID, text: String) -> Bool {
        let utf8 = text.utf8
        let scanned = closeTagScanOffsets[chatID] ?? 0
        let start = scanned <= utf8.count ? max(0, scanned - (Self.closeTag.utf8.count - 1)) : 0
        closeTagScanOffsets[chatID] = utf8.count
        let tail = utf8[utf8.index(utf8.startIndex, offsetBy: start)...]
        return tail.firstRange(of: Self.closeTag.utf8) != nil
    }

    /// Ends the live reasoning phase and hands its timing and expansion state to the persisted message.
    func finishStream(chatID: UUID, token: UUID, messageID: Int64?) {
        guard activeStreams[chatID] == token else { return }
        activeStreams[chatID] = nil
        closeTagScanOffsets[chatID] = nil
        let liveKey = ReasoningKey.live(chatID: chatID)
        let liveTiming = timings.removeValue(forKey: liveKey)
        let liveExpansion = expansion.removeValue(forKey: liveKey)
        guard let messageID else { return }

        let messageKey = ReasoningKey(chatID: chatID, messageID: messageID)
        if var timing = liveTiming {
            if timing.end == nil {
                timing.end = Date()
            }
            timings[messageKey] = timing
        }
        else if timings[messageKey] != nil {
            timings[messageKey] = nil
        }
        // Message IDs can be reused after deletion, so never carry over a stale expansion state.
        if expansion[messageKey] != liveExpansion {
            expansion[messageKey] = liveExpansion
        }
    }
}

/// Records when `<think>` and `</think>` first appear in a stream fed chunk by chunk, for streams that don't go
/// through `ReasoningTimingStore` (compare columns, Quick Chat).
struct ReasoningTagTimer {
    private(set) var start: Date?
    private(set) var end: Date?
    private var tail = ""
    private var consumedLength = 0

    private static let openTag = "<think>"
    private static let closeTag = "</think>"
    private static let openTagSearchWindow = 256

    mutating func consume(_ chunk: String, at date: Date = Date()) {
        guard end == nil, !chunk.isEmpty else { return }
        // Keeping the previous chunk's tail finds tags split across chunks.
        let window = tail + chunk
        if start == nil, consumedLength < Self.openTagSearchWindow, window.contains(Self.openTag) {
            start = date
        }
        if start != nil, window.contains(Self.closeTag) {
            end = date
        }
        consumedLength += chunk.count
        tail = String(window.suffix(Self.closeTag.count - 1))
    }

    /// Reasoning that never closed ends when the response finished.
    func interval(finishedAt: Date) -> (start: Date?, end: Date?) {
        guard let start else { return (nil, nil) }
        return (start, end ?? finishedAt)
    }
}

struct ThinkingProcessView: View {
    let content: String
    /// True while the reasoning is still streaming and no answer text has arrived yet.
    var isThinking: Bool = false
    var timingKey: ReasoningKey?
    /// Reasoning duration saved with the message; preferred over the session-only timing store.
    var persistedDuration: TimeInterval?

    @AppStorage("expandReasoningByDefault") private var expandReasoningByDefault: Bool = false
    @ObservedObject private var timingStore = ReasoningTimingStore.shared
    @State private var localExpanded: Bool?
    @State private var localStart = Date()

    private var timing: ReasoningTimingStore.Timing? {
        timingKey.flatMap { timingStore.timing(for: $0) }
    }

    private var completedDuration: TimeInterval? {
        persistedDuration ?? timing?.duration
    }

    private var isExpanded: Bool {
        if let timingKey, let stored = timingStore.isExpanded(timingKey) {
            return stored
        }
        if let localExpanded {
            return localExpanded
        }
        return expandReasoningByDefault
    }

    var body: some View {
        // Steps are only needed once reasoning is done; skip parsing on every streamed chunk.
        let steps = isThinking ? [] : ReasoningStepParser.parse(content)

        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleExpanded) {
                if isThinking {
                    liveHeader
                }
                else {
                    completedHeader(stepCount: steps.count)
                }
            }
            .buttonStyle(PlainButtonStyle())
            .help(isExpanded ? "Hide reasoning" : "Show reasoning")

            if isExpanded {
                expandedBody(steps: steps)
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.25))
                            .frame(width: 1.5)
                    }
                    .padding(.leading, 12)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func expandedBody(steps: [ReasoningStep]) -> some View {
        if isThinking || steps.isEmpty {
            Text(content)
                .foregroundColor(.gray)
        }
        else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                    VStack(alignment: .leading, spacing: 3) {
                        if let title = step.title {
                            Text(title)
                                .font(.callout.weight(.semibold))
                                .foregroundColor(.secondary)
                        }
                        if !step.body.isEmpty {
                            Text(step.body)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var liveHeader: some View {
        let start = timing?.start ?? localStart

        return HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)
                .frame(width: 12, height: 12)

            TimelineView(.periodic(from: start, by: 1)) { context in
                Text("Thinking \(Self.formatDuration(context.date.timeIntervalSince(start)))")
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            .fixedSize()

            if let sentence = Self.latestSentence(in: content) {
                Text(sentence)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }

    private func completedHeader(stepCount: Int) -> some View {
        HStack(spacing: 5) {
            if let duration = completedDuration {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .semibold))
                Text("Thought for \(Self.formatDuration(max(duration, 1)))" + Self.stepSuffix(stepCount))
            }
            else {
                Text("Thought process" + Self.stepSuffix(stepCount))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .rotationEffect(.degrees(isExpanded ? 90 : 0))

            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .contentShape(Rectangle())
    }

    private func toggleExpanded() {
        let newValue = !isExpanded
        withAnimation(.easeInOut(duration: 0.2)) {
            if let timingKey {
                timingStore.setExpanded(newValue, for: timingKey)
            }
            else {
                localExpanded = newValue
            }
        }
    }

    static func stepSuffix(_ stepCount: Int) -> String {
        stepCount > 1 ? " · \(stepCount) steps" : ""
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        guard seconds >= 60 else { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    /// Returns the most recent sentence of the reasoning, preferring the last finished one over a short fragment
    /// that is still streaming in.
    static func latestSentence(in text: String) -> String? {
        let tail = text.suffix(600)
        guard
            let lastLine = tail.split(whereSeparator: \.isNewline).last(where: {
                !$0.trimmingCharacters(in: .whitespaces).isEmpty
            })
        else { return nil }

        let cleaned =
            lastLine
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ").union(.whitespaces))
        guard !cleaned.isEmpty else { return nil }

        var sentences: [String] = []
        cleaned.enumerateSubstrings(in: cleaned.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty {
                sentences.append(sentence)
            }
        }

        guard let last = sentences.last else { return cleaned }
        let isUnfinished = !(last.last.map { ".!?:".contains($0) } ?? false)
        if isUnfinished, last.count < 24, sentences.count > 1 {
            return sentences[sentences.count - 2]
        }
        return last
    }
}
