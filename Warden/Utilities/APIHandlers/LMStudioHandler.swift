import Foundation

/// Handler for LM Studio API integration.
/// LM Studio provides OpenAI-compatible endpoints for local LLM inference.
/// This handler inherits from ChatGPTHandler since the API is fully compatible.
class LMStudioHandler: ChatGPTHandler {
    
    override init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        super.init(config: config, session: session, streamingSession: streamingSession)
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
    }
    
    /// LM Studio uses the same OpenAI-compatible API format, so we inherit all functionality
    /// from ChatGPTHandler. The main differences are:
    /// - Different base URL (typically http://localhost:1234/v1/chat/completions)
    /// - No API key required (local service)
    /// - Different model names based on locally loaded models
    
    /// Override fetchModels to handle LM Studio's models endpoint
    override func fetchModels() async throws -> [AIModel] {
        // LM Studio uses the same /v1/models endpoint as OpenAI
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        
        // Add authorization header if API key is provided
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                // Use the same response format as OpenAI
                let gptResponse = try JSONDecoder().decode(ChatGPTModelsResponse.self, from: responseData)
                return gptResponse.data.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }
    

}

// MARK: - Private helper for ChatGPTModelsResponse
private struct ChatGPTModelsResponse: Codable {
    let data: [ChatGPTModel]
}

private struct ChatGPTModel: Codable {
    let id: String
} 
