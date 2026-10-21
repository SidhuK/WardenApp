import AppKit
import CoreData
import SwiftUI

/// Formatting for the compact metadata shown under assistant replies.
enum ReplyFooterFormatting {
    /// Compact token count such as "842", "1.2k", "12k" or "1.5M".
    static func tokenCount(_ count: Int) -> String {
        let value = max(0, count)
        if value < 1000 {
            return "\(value)"
        }
        // Switch units before rounding would produce "1000k".
        if value < 999_500 {
            return compact(Double(value) / 1000) + "k"
        }
        return compact(Double(value) / 1_000_000) + "M"
    }

    static func tokens(_ count: Int) -> String {
        "\(tokenCount(count)) \(count == 1 ? "token" : "tokens")"
    }

    /// Estimated cost such as "$0.0031", "<$0.0001" or "$1.25"; nil when the cost is unknown.
    static func cost(_ usd: Double?) -> String? {
        guard let usd, usd.isFinite, usd >= 0 else { return nil }
        if usd == 0 { return "$0.00" }
        if usd < 0.0001 { return "<$0.0001" }
        if usd < 1 { return String(format: "$%.4f", usd) }
        return String(format: "$%.2f", usd)
    }

    /// Duration such as "4.2s" or "1m 5s".
    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, seconds)
        if value < 0.05 { return "<0.1s" }
        if value < 59.95 { return String(format: "%.1fs", value) }
        let total = Int(value.rounded())
        return "\(total / 60)m \(total % 60)s"
    }

    static func tokenBreakdown(_ usage: TokenUsage) -> String {
        var input = "Input: \(usage.inputTokens.formatted()) tokens"
        if let cached = usage.cachedInputTokens, cached > 0 {
            input += " (\(cached.formatted()) cached)"
        }
        var output = "Output: \(usage.outputTokens.formatted()) tokens"
        if let reasoning = usage.reasoningTokens, reasoning > 0 {
            output += " (\(reasoning.formatted()) reasoning)"
        }
        return [input, output, "Total: \(usage.totalTokens.formatted()) tokens"].joined(separator: "\n")
    }

    static func durationBreakdown(_ metrics: MessageMetrics) -> String? {
        var lines: [String] = []
        if let total = metrics.totalDuration {
            lines.append("Total: \(duration(total))")
        }
        if let ttft = metrics.timeToFirstToken {
            lines.append("Time to first token: \(duration(ttft))")
        }
        if let reasoning = metrics.reasoningDuration {
            lines.append("Reasoning: \(duration(reasoning))")
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func compact(_ value: Double) -> String {
        if value < 9.95 {
            let formatted = String(format: "%.1f", value)
            return formatted.hasSuffix(".0") ? String(formatted.dropLast(2)) : formatted
        }
        return String(format: "%.0f", value)
    }
}

/// Always-visible metadata and actions under a finished assistant reply.
struct ReplyFooterView: View {
    @ObservedObject var message: MessageEntity
    let modelName: String?
    let modelID: String?
    let timestamp: String
    let isLatestMessage: Bool
    let isCopied: Bool
    let onCopy: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            metadata
                .padding(.trailing, 6)
            actions
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var metadata: some View {
        let metrics = message.metrics
        return HStack(spacing: 4) {
            if let modelName {
                Text(modelName)
                    .lineLimit(1)
                    .help(modelID ?? modelName)
            }
            if let usage = metrics?.usage, usage.totalTokens > 0 {
                separator
                Text(ReplyFooterFormatting.tokens(usage.totalTokens))
                    .help(ReplyFooterFormatting.tokenBreakdown(usage))
            }
            if let cost = ReplyFooterFormatting.cost(metrics?.costUSD) {
                separator
                Text(cost)
                    .help("Estimated cost")
            }
            if let metrics, let total = metrics.totalDuration {
                separator
                Text(ReplyFooterFormatting.duration(total))
                    .help(ReplyFooterFormatting.durationBreakdown(metrics) ?? "")
            }
            if !timestamp.isEmpty {
                separator
                Text(timestamp)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private var separator: some View {
        Text("·")
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var actions: some View {
        FooterIconButton(
            icon: isCopied ? "checkmark" : "doc.on.doc",
            label: isCopied ? "Copied" : "Copy reply",
            action: onCopy
        )

        if isLatestMessage {
            if message.chat?.isTemporary == true {
                FooterIconButton(icon: "arrow.clockwise", label: "Retry") {
                    NotificationCenter.default.post(name: .retryMessage, object: nil)
                }
            } else {
                RetryMenuButton(message: message)
            }
        }

        // Branches are separate chats in the history, which a temporary chat isn't part of.
        if message.chat?.isTemporary != true {
            BranchToolbarButton(message: message)
                .accessibilityLabel("Branch from this reply")
        }

        Menu {
            if let modelID, !modelID.isEmpty {
                Button("Copy Model ID") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(modelID, forType: .string)
                }
                Divider()
            }
            Button("Delete Message…", role: .destructive, action: onDelete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(.horizontal, 6)
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}

/// Retry button whose menu re-asks the same question with another model. The new answer becomes a branch,
/// so the original reply is kept and both stay reachable from the branch popover.
private struct RetryMenuButton: View {
    @ObservedObject var message: MessageEntity

    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>
    @ObservedObject private var favorites = FavoriteModelsManager.shared

    var body: some View {
        Menu {
            let choices = modelChoices
            if choices.isEmpty {
                Text("Favorite a model to retry with it here")
            } else {
                if !choices.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(choices.favorites) { choice in
                            choiceButton(choice)
                        }
                    }
                }
                if !choices.recent.isEmpty {
                    Section("Recent") {
                        ForEach(choices.recent) { choice in
                            choiceButton(choice)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 10, weight: .medium))
        } primaryAction: {
            NotificationCenter.default.post(name: .retryMessage, object: nil)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 6)
        .help("Retry (⌘R). Open the menu to retry with another model as a branch.")
        .accessibilityLabel("Retry")
    }

    private func choiceButton(_ choice: ErrorModelChoice) -> some View {
        Button {
            retry(with: choice)
        } label: {
            Text("\(ModelMetadata.formatModelComponents(modelId: choice.modelId, provider: choice.providerType).displayName) · \(choice.providerName)")
        }
    }

    private var modelChoices: RetryModelChoices.Choices {
        var configured: [String: String] = [:]
        for service in apiServices {
            guard let type = service.type, configured[type] == nil else { continue }
            configured[type] = service.name ?? type
        }
        let chat = message.chat
        return RetryModelChoices.build(
            favorites: favorites.getAllFavorites(),
            recent: RecentModelsStore.all(),
            configuredProviders: configured,
            currentProvider: nonEmpty(message.agentServiceType) ?? chat?.apiService?.type,
            currentModel: nonEmpty(message.agentModel) ?? chat?.gptModel
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    @MainActor
    private func retry(with choice: ErrorModelChoice) {
        guard let chat = message.chat,
              let question = chat.messagesArray
                .filter({ $0.own && $0.id < message.id })
                .max(by: { $0.id < $1.id }),
              let service = apiServices.first(where: { $0.type == choice.providerType })
        else {
            showToast("Couldn't find the question to retry", icon: "exclamationmark.triangle")
            return
        }

        RecentModelsStore.record(provider: choice.providerType, model: choice.modelId)
        let context = viewContext
        Task { @MainActor in
            do {
                _ = try await ChatBranchingManager(viewContext: context).createBranch(
                    from: chat,
                    at: question,
                    origin: .user,
                    targetService: service,
                    targetModel: choice.modelId,
                    autoGenerate: true
                )
            } catch {
                showToast(error.localizedDescription, icon: "exclamationmark.triangle")
            }
        }
    }

    private func showToast(_ message: String, icon: String) {
        NotificationCenter.default.post(
            name: AppConstants.showToastNotification,
            object: nil,
            userInfo: ["message": message, "icon": icon]
        )
    }
}

private struct FooterIconButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    var body: some View {
        ToolbarButton(icon: icon, text: "", action: action)
            .help(label)
            .accessibilityLabel(label)
    }
}
