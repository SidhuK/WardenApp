
import Foundation
import os

private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaModel: Codable {
    let name: String
}

class OllamaHandler: BaseAPIHandler {
    
    override func fetchModels() async throws -> [AIModel] {
        let tagsURL = baseURL.deletingLastPathComponent().appendingPathComponent("tags")
        
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await session.data(for: request)
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }
                
                let ollamaResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: responseData)
                
                return ollamaResponse.models.map { AIModel(id: $0.name) }
                
            case .failure(let error):
                throw error
            }
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    override func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": requestMessages,
            "temperature": temperature,
        ]
        
        // Add tools if present
        if let tools = tools, !tools.isEmpty {
            jsonDict["tools"] = tools
            // Ollama uses 'tool_choice' similar to OpenAI? 
            // According to Ollama docs, it supports function calling.
            // We'll assume auto is default or explicitly set it if needed.
            // For now, let's not force it unless we know Ollama requires it.
            // Actually, OpenAI uses "tool_choice": "auto".
            // Let's add it.
            // Note: Check if Ollama supports "tool_choice".
            // Recent Ollama versions do.
            // jsonDict["tool_choice"] = "auto" 
        }

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            WardenLog.app.debug("Ollama response received: \(responseString.count, privacy: .public) char(s)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    if let message = dict["message"] as? [String: Any],
                        let messageRole = message["role"] as? String,
                        let messageContent = message["content"] as? String
                    {
                        return (messageContent, messageRole, nil)
                    }
                }
            }
            catch {
                WardenLog.app.error("Ollama JSON parse error: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil, nil)
        }

        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any] {
                if let message = dict["message"] as? [String: Any],
                    let messageRole = message["role"] as? String,
                    let done = dict["done"] as? Bool,
                    let messageContent = message["content"] as? String
                {
                    return (done, nil, messageContent, messageRole, nil)
                }
            }

        }
        catch {
            #if DEBUG
            WardenLog.app.debug(
                "Ollama delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif

            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }
}
