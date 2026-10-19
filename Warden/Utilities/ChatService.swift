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
        onChunk: @MainActor @escaping (String) async -> Void
    ) async throws -> StreamOutcome {
        return try await APIServiceManager.handleStream(
            apiService: apiService,
            messages: messages,
            tools: tools,
            settings: settings,
            onChunk: onChunk
        )
    }
    
    /// Send a message with non-streaming response
    func sendMessage(
        apiService: APIService,
        messages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings,
        completion: @escaping (Result<StreamChunk, Error>) -> Void
    ) {
        apiService.sendMessageWithUsage(messages, tools: tools, settings: settings) { result in
            completion(result.mapError { $0 as Error })
        }
    }
}
