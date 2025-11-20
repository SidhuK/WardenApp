
import Foundation

private struct ClaudeModelsResponse: Codable {
    let data: [ClaudeModel]
}

private struct ClaudeModel: Codable {
    let id: String
}

class ClaudeHandler: BaseAPIHandler {
    
    override init(config: APIServiceConfiguration, session: URLSession) {
        super.init(config: config, session: session)
    }

    override func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL.deletingLastPathComponent().appendingPathComponent("models")
        
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("2023-06-01", forHTTPHeaderField: "Anthropic-Version")
        
        do {
            let (data, response) = try await session.data(for: request)
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }
                
                let claudeResponse = try JSONDecoder().decode(ClaudeModelsResponse.self, from: responseData)
                
                return claudeResponse.data.map { AIModel(id: $0.id) }
                
            case .failure(let error):
                throw error
            }
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    override func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "Anthropic-Version")

        // Claude doesn't support 'system' role. Instead, we extract system message from request messages and insert into 'system' string parameter (more details: https://docs.anthropic.com/en/api/messages)
        var systemMessage = ""
        let firstMessage = requestMessages.first
        var updatedRequestMessages = requestMessages

        if firstMessage?["role"] as? String == "system" {
            systemMessage = firstMessage?["content"] as? String ?? ""
            updatedRequestMessages.removeFirst()
        }

        let maxTokens =
            model == "claude-3-5-sonnet-latest" ? 8192 : AppConstants.defaultApiConfigurations["claude"]!.maxTokens!

        let jsonDict: [String: Any] = [
            "model": model,
            "messages": updatedRequestMessages,
            "system": systemMessage,
            "stream": stream,
            "temperature": temperature,
            "max_tokens": maxTokens,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }



    override func parseJSONResponse(data: Data) -> (String, String)? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let role = json["role"] as? String,
                let contentArray = json["content"] as? [[String: Any]]
            {

                let textContent = contentArray.compactMap { item -> String? in
                    if let type = item["type"] as? String, type == "text",
                        let text = item["text"] as? String
                    {
                        return text
                    }
                    return nil
                }.joined(separator: "\n")

                if !textContent.isEmpty {
                    return (textContent, role)
                }
            }
        }
        catch {
            print("Error parsing JSON: \(error.localizedDescription)")
        }
        return nil
    }

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            return (false, nil, nil, nil)
        }
        
        var isFinished = false
        var textContent = ""
        var parseError: Error?
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            parseError = NSError(
                domain: "SSEParsing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"]
            )
            return (isFinished, parseError, nil, nil)
        }

        if let eventType = json["type"] as? String {
            switch eventType {
            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any],
                    let text = contentBlock["text"] as? String
                {
                    textContent = text
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any],
                    let text = delta["text"] as? String
                {
                    textContent += text
                }
            case "message_delta":
                if let delta = json["delta"] as? [String: Any],
                    let stopReason = delta["stop_reason"] as? String
                {
                    isFinished = stopReason == "end_turn"
                }
            case "message_stop":
                isFinished = true
            case "ping":
                // Ignore ping events
                break
            default:
                // Ignore other events
                break
            }
        }
        return (isFinished, parseError, textContent.isEmpty ? nil : textContent, nil)
    }
}
