import Foundation

/// Service responsible for handling chat message sending logic
/// Unifies single and multi-agent message sending patterns
class ChatService {
    static let shared = ChatService()

    private init() {}

    /// Send a message with streaming response
    func sendStream(
        apiService: APIService,
        messages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings,
        chatID: UUID? = nil,
        onChunk: @MainActor @escaping (String) async -> Void
    ) async throws -> [ToolCall]? {
        return try await APIServiceManager.handleStream(
            apiService: apiService,
            messages: messages,
            tools: tools,
            settings: settings,
            chatID: chatID,
            onChunk: onChunk
        )
    }

    /// Send a message with non-streaming response
    func sendMessage(
        apiService: APIService,
        messages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings,
        chatID: UUID? = nil,
        completion: @escaping (Result<(String?, [ToolCall]?), Error>) -> Void
    ) {
        let requestID = apiService.beginUsageCapture()
        apiService.sendMessage(messages, tools: tools, settings: settings) { [weak self] result in
            // Record token usage captured by the handler for this non-streaming
            // completion (best effort — usage accounting must never break a chat).
            // Only the main chat path passes a chatID; auxiliary calls (chat-name
            // generation, connection tests) leave it nil and are not tracked.
            if let self, let chatID {
                let usage = apiService.consumeCapturedUsage(for: requestID)
                if let usage, !usage.isEmpty {
                    Task { @MainActor in
                        UsageTrackingService.shared.record(
                            usage: usage,
                            providerName: apiService.name,
                            modelId: apiService.model,
                            chatID: chatID
                        )
                    }
                }
            }
            completion(result.mapError { $0 as Error })
        }
    }
}
