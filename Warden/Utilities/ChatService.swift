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
            // Close the capture scope on every exit path so captured usage never
            // lingers on the handler. Only main-chat completions (chatID passed)
            // are recorded; auxiliary calls (chat-name generation, connection
            // tests) have their partial usage discarded. Best effort — usage
            // accounting must never break a chat.
            let usage = apiService.consumeCapturedUsage(for: requestID)
            if let self, let chatID, let usage, !usage.isEmpty {
                Task { @MainActor in
                    UsageTrackingService.shared.record(
                        usage: usage,
                        providerName: apiService.name,
                        modelId: apiService.model,
                        chatID: chatID
                    )
                }
            }
            completion(result.mapError { $0 as Error })
        }
    }
}
