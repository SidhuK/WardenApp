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
        temperature: Float,
        onChunk: @escaping (String, String) async -> Void
    ) async throws -> String {
        // Note: Streaming tool calls is not yet fully supported in the return type here.
        // We return String for now to maintain compatibility, but APIServiceManager handles the stream.
        // To fully support streaming tools, we would need to change this return type or handle it via callback.
        // For this iteration, we focus on non-streaming tools or accumulating text.
        return try await APIServiceManager.handleStream(
            apiService: apiService,
            messages: messages,
            tools: tools,
            temperature: temperature,
            onChunk: onChunk
        )
    }
    
    /// Send a message with non-streaming response
    func sendMessage(
        apiService: APIService,
        messages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), Error>) -> Void
    ) {
        apiService.sendMessage(messages, tools: tools, temperature: temperature) { result in
            completion(result.mapError { $0 as Error })
        }
    }
}
