
import SwiftUI

struct MultiAgentResponseView: View {
    let responses: [MultiAgentMessageManager.AgentResponse]
    let isProcessing: Bool
    let onContinue: (MultiAgentMessageManager.AgentResponse) -> Void
    let onAskAllFollowUp: () -> Void
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @AppStorage("compareSyncScroll") private var syncScroll: Bool = false

    private var badges: [UUID: Set<CompareBadge>] {
        CompareStats.badges(
            for: responses.map { response in
                CompareCandidate(
                    id: response.id,
                    isSuccessful: response.isSuccessful,
                    totalDuration: response.metrics.totalDuration,
                    costUSD: response.costUSD
                )
            }
        )
    }

    private var allFinished: Bool {
        !isProcessing && !responses.isEmpty && responses.allSatisfy(\.isComplete)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isProcessing && responses.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Sending to multiple AI services...")
                        .font(.system(size: chatFontSize))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                header

                let columnBadges = badges
                HStack(alignment: .top, spacing: 12) {
                    ForEach(responses) { response in
                        AgentResponseColumn(
                            response: response,
                            badges: columnBadges[response.id] ?? [],
                            syncScroll: syncScroll,
                            onContinue: {
                                onContinue(response)
                            }
                        )
                        .frame(maxWidth: .infinity)
                    }
                }

                if allFinished {
                    HStack {
                        Spacer()
                        Button(action: onAskAllFollowUp) {
                            Label("Ask All a Follow-up", systemImage: "arrowshape.turn.up.left.2")
                        }
                        .controlSize(.small)
                        .help("Keep comparing these models and type a follow-up question")
                    }
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .padding(.horizontal, 16)
    }

    private var header: some View {
        HStack {
            Text("Comparing \(responses.count) \(responses.count == 1 ? "model" : "models")")
                .font(.system(size: chatFontSize - 2, weight: .medium))
                .foregroundColor(.secondary)

            Spacer()

            Toggle("Sync scroll", isOn: $syncScroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: chatFontSize - 3))
                .foregroundColor(.secondary)
                .help("Show answers at full height so they scroll together with the chat")
        }
    }
}

struct AgentResponseColumn: View {
    let response: MultiAgentMessageManager.AgentResponse
    let badges: Set<CompareBadge>
    let syncScroll: Bool
    let onContinue: () -> Void
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @Environment(\.colorScheme) private var colorScheme

    private var serviceLogoName: String {
        "logo_\(response.serviceType)"
    }

    /// Human-readable model name, e.g. "anthropic/claude-sonnet-4.5" -> "Claude Sonnet 4.5".
    private var modelDisplayName: String {
        let displayName = ModelMetadata.formatModelComponents(modelId: response.model).displayName
        return displayName.isEmpty ? response.model : displayName
    }

    private var isRunning: Bool {
        !response.isComplete && response.error == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with service logo and status
            HStack {
                HStack(spacing: 8) {
                    // Service logo (same as used in chat title)
                    Image(serviceLogoName)
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .frame(width: 16, height: 16)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(modelDisplayName)
                            .font(.system(size: chatFontSize - 1, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(response.serviceName)
                            .font(.system(size: chatFontSize - 3))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .help("\(response.model) via \(response.serviceName)")

                Spacer()

                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
            }

            statsRow

            // Progress indicator for ongoing requests
            if isRunning {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing...")
                        .font(.system(size: chatFontSize - 2))
                        .foregroundColor(.secondary)
                        .italic()
                }
            }

            Divider()
                .opacity(0.5)

            if syncScroll {
                responseContent
            } else {
                ScrollView {
                    responseContent
                }
                .frame(maxHeight: 400)
            }

            // Footer with the pick action and timestamp
            HStack {
                if response.isSuccessful {
                    Button(action: onContinue) {
                        Label("Use This Answer", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Continue the conversation with this model")
                }

                Spacer()

                Text(timeString)
                    .font(.system(size: chatFontSize - 3))
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(cardBackgroundColor)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
    }

    private var responseContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = response.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(errorMessage(for: error))
                        .font(.system(size: chatFontSize - 1))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            } else if !response.response.isEmpty {
                AgentResponseMarkdownContent(
                    text: response.response,
                    reasoningDuration: response.metrics.reasoningDuration,
                    isStreaming: !response.isComplete,
                    fontSize: chatFontSize,
                    colorScheme: colorScheme
                )
                .equatable()
            } else {
                Text(response.isComplete ? "No response" : "Waiting for response...")
                    .font(.system(size: chatFontSize))
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        if response.requestStart != nil || !badges.isEmpty {
            HStack(spacing: 6) {
                if isRunning, let requestStart = response.requestStart {
                    TimelineView(.periodic(from: .now, by: 0.1)) { context in
                        statsText(elapsed: context.date.timeIntervalSince(requestStart))
                    }
                } else {
                    statsText(elapsed: nil)
                }

                Spacer(minLength: 4)

                ForEach(CompareBadge.allCases.filter { badges.contains($0) }, id: \.self) { badge in
                    CompareBadgeView(badge: badge, fontSize: chatFontSize - 4)
                }
            }
        }
    }

    /// While streaming `elapsed` is the live time since the request started; once complete the saved totals are used.
    private func statsText(elapsed: TimeInterval?) -> some View {
        let metrics = response.metrics
        var parts: [String] = []
        if let ttft = metrics.timeToFirstToken {
            parts.append("TTFT \(CompareStats.formatDuration(ttft))")
        }
        if let total = elapsed ?? metrics.totalDuration {
            parts.append(CompareStats.formatDuration(total))
        }
        if let cost = response.costUSD {
            parts.append(CompareStats.formatCost(cost))
        }

        return Text(parts.joined(separator: " · "))
            .font(.system(size: chatFontSize - 3).monospacedDigit())
            .foregroundColor(.secondary)
            .lineLimit(1)
            .help(statsTooltip)
    }

    private var statsTooltip: String {
        var lines: [String] = []
        if let ttft = response.metrics.timeToFirstToken {
            lines.append("Time to first token: \(CompareStats.formatDuration(ttft))")
        }
        if let total = response.metrics.totalDuration {
            lines.append("Total time: \(CompareStats.formatDuration(total))")
        }
        if let usage = response.usage {
            lines.append(CompareStats.formatTokens(usage))
        }
        if let cost = response.costUSD {
            lines.append("Estimated cost: \(CompareStats.formatCost(cost))")
        } else if response.usage != nil {
            lines.append("Cost unknown for this model")
        }
        return lines.joined(separator: "\n")
    }

    private var statusColor: Color {
        if response.error != nil {
            return .red
        } else if response.isComplete {
            return .green
        } else {
            return .orange
        }
    }

    private var cardBackgroundColor: Color {
        Color(NSColor.textBackgroundColor)
    }

    private var borderColor: Color {
        if response.error != nil {
            return .red.opacity(0.3)
        } else if response.isComplete {
            return .green.opacity(0.3)
        } else {
            return .orange.opacity(0.3)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: response.timestamp)
    }

    private func errorMessage(for error: APIError) -> String {
        switch error.base {
        case .unauthorized:
            return "Authentication failed - check API key"
        case .rateLimited:
            return "Rate limit exceeded - please wait"
        case .serverError(let message):
            return "Server error: \(message)"
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .noApiService(let message):
            return message
        case .decodingFailed(let message):
            return "Decode error: \(message)"
        case .invalidResponse:
            return "Invalid response from service"
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .overloaded:
            return "Server error: \(error.context?.message ?? "Provider overloaded")"
        case .withContext:
            return "Unknown error"
        }
    }
}

private struct CompareBadgeView: View {
    let badge: CompareBadge
    let fontSize: Double

    private var tint: Color {
        switch badge {
        case .fastest: return .orange
        case .cheapest: return .green
        }
    }

    var body: some View {
        Label(badge.title, systemImage: badge.systemImage)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundColor(tint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}

/// Renders a compare column's response through the same parsing/Markdown pipeline as normal assistant replies.
/// Equatable so columns whose text hasn't changed skip re-parsing when a sibling column streams a new chunk.
private struct AgentResponseMarkdownContent: View, Equatable {
    let text: String
    let reasoningDuration: TimeInterval?
    let isStreaming: Bool
    let fontSize: Double
    let colorScheme: ColorScheme

    var body: some View {
        MessageContentView(
            message: text,
            isStreaming: isStreaming,
            own: false,
            effectiveFontSize: fontSize,
            colorScheme: colorScheme,
            reasoningDuration: reasoningDuration
        )
        .foregroundColor(.primary)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    let start = Date().addingTimeInterval(-6)
    MultiAgentResponseView(
        responses: [
            MultiAgentMessageManager.AgentResponse(
                serviceName: "OpenAI",
                serviceType: "chatgpt",
                model: "gpt-4",
                response: "This is a sample response from GPT-4. It's quite detailed and shows how the multi-agent system works.",
                isComplete: true,
                error: nil,
                timestamp: Date(),
                usage: TokenUsage(inputTokens: 1200, outputTokens: 340),
                requestStart: start,
                firstTokenAt: start.addingTimeInterval(0.8),
                finishedAt: start.addingTimeInterval(4.2),
                costUSD: 0.0031
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Anthropic",
                serviceType: "claude",
                model: "anthropic/claude-sonnet-4.5",
                response: """
                    ## Summary

                    Here's **Claude's** perspective:

                    - Point one
                    - Uses `inline code`

                    ```swift
                    print("hi")
                    ```
                    """,
                isComplete: true,
                error: nil,
                timestamp: Date(),
                usage: TokenUsage(inputTokens: 1200, outputTokens: 410),
                requestStart: start,
                firstTokenAt: start.addingTimeInterval(1.1),
                finishedAt: start.addingTimeInterval(5.6),
                costUSD: 0.0098
            ),
            MultiAgentMessageManager.AgentResponse(
                serviceName: "Google",
                serviceType: "gemini",
                model: "gemini-pro",
                response: "",
                isComplete: true,
                error: APIError.unauthorized,
                timestamp: Date()
            )
        ],
        isProcessing: false,
        onContinue: { _ in },
        onAskAllFollowUp: {}
    )
    .frame(width: 800, height: 500)
}
