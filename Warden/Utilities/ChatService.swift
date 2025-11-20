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
        temperature: Float,
        onChunk: @escaping (String, String) async -> Void
    ) async throws -> String {
        return try await APIServiceManager.handleStream(
            apiService: apiService,
            messages: messages,
            temperature: temperature,
            onChunk: onChunk
        )
    }
    
    /// Send a message with non-streaming response
    func sendMessage(
        apiService: APIService,
        messages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        apiService.sendMessage(messages, temperature: temperature) { result in
            completion(result.mapError { $0 as Error })
        }
    }
}
