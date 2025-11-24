import CoreData
import Foundation

/// Handler for LM Studio API integration.
/// LM Studio provides OpenAI-compatible endpoints for local LLM inference.
/// This handler inherits from ChatGPTHandler since the API is fully compatible.
class LMStudioHandler: ChatGPTHandler {
    
    override init(config: APIServiceConfiguration, session: URLSession) {
        super.init(config: config, session: session)
    }
    
    /// LM Studio uses the same OpenAI-compatible API format, so we inherit all functionality
    /// from ChatGPTHandler. The main differences are:
    /// - Different base URL (typically http://localhost:1234/v1/chat/completions)
    /// - No API key required (local service)
    /// - Different model names based on locally loaded models
    
    /// Override the prepare request to handle LM Studio specific requirements
    override internal func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String, 
        temperature: Float, 
        stream: Bool
    ) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        
        // LM Studio typically doesn't require authentication for local instances
        // But we'll include the API key if provided for compatibility
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // LM Studio doesn't have reasoning models, so use temperature as provided
        let temperatureOverride = temperature

        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                // Handle image attachments the same way as OpenAI
                let pattern = "<image-uuid>(.*?)</image-uuid>"

                if content.range(of: pattern, options: .regularExpression) != nil {
                    let textContent = content.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    var contentArray: [[String: Any]] = []

                    if !textContent.isEmpty {
                        contentArray.append(["type": "text", "text": textContent])
                    }

                    let regex = try? NSRegularExpression(pattern: pattern, options: [])
                    let nsString = content as NSString
                    let matches =
                        regex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
                        ?? []

                    for match in matches {
                        let uuidRange = match.range(at: 1)
                        if uuidRange.location != NSNotFound {
                            let uuid = nsString.substring(with: uuidRange)
                            if let uuid = UUID(uuidString: uuid),
                               let imageData = self.dataLoader.loadImageData(uuid: uuid) {
                                let base64Image = imageData.base64EncodedString()
                                contentArray.append([
                                    "type": "image_url",
                                    "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]
                                ])
                            }
                        }
                    }

                    processedMessage["content"] = contentArray
                } else {
                    processedMessage["content"] = content
                }
            }

            processedMessages.append(processedMessage)
        }

        let requestBody: [String: Any] = [
            "model": model,
            "messages": processedMessages,
            "temperature": temperatureOverride,
            "stream": stream,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            print("Error serializing request body: \(error)")
        }

        return request
    }

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