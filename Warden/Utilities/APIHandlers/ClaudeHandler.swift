
import Foundation
import os

private struct ClaudeModelsResponse: Codable {
    let data: [ClaudeModel]
}

private struct ClaudeModel: Codable {
    let id: String
}

class ClaudeHandler: BaseAPIHandler {
    
    override init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        super.init(config: config, session: session, streamingSession: streamingSession)
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
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

    override func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        stream: Bool
    ) throws -> URLRequest {
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

        let defaultMaxTokens = AppConstants.defaultApiConfigurations["claude"]?.maxTokens ?? 8192
        var maxTokens = (model == "claude-3-5-sonnet-latest") ? 8192 : defaultMaxTokens

        if let desiredBudget = settings.reasoningEffort.anthropicThinkingBudgetTokens {
            let budget = min(max(desiredBudget, 1024), 128000)
            maxTokens = max(maxTokens, budget + 4096)
            
            var jsonDict: [String: Any] = [
                "model": model,
                "messages": updatedRequestMessages,
                "system": systemMessage,
                "stream": stream,
                "max_tokens": maxTokens,
            ]
            
            jsonDict["thinking"] = [
                "type": "enabled",
                "budget_tokens": budget
            ]
            
            if let tools = tools {
                jsonDict["tools"] = tools
            }

            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }

            return request
        }

        var jsonDict: [String: Any] = [
            "model": model,
            "messages": updatedRequestMessages,
            "system": systemMessage,
            "stream": stream,
            "temperature": settings.temperature,
            "max_tokens": maxTokens,
        ]
        
        // Add tools if provided
        if let tools = tools {
            jsonDict["tools"] = tools
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }

        return request
    }



    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                let role = json["role"] as? String,
                let contentArray = json["content"] as? [[String: Any]]
            {

                let thinkingContent = contentArray.compactMap { item -> String? in
                    if let type = item["type"] as? String,
                       type == "thinking",
                       let thinking = (item["thinking"] as? String) ?? (item["text"] as? String) {
                        return thinking
                    }
                    return nil
                }.joined(separator: "\n")

                let textContent = contentArray.compactMap { item -> String? in
                    if let type = item["type"] as? String, type == "text",
                        let text = item["text"] as? String
                    {
                        return text
                    }
                    return nil
                }.joined(separator: "\n")

                if !thinkingContent.isEmpty || !textContent.isEmpty {
                    let finalContent: String
                    if !thinkingContent.isEmpty {
                        if textContent.isEmpty {
                            finalContent = "<think>\n\(thinkingContent)\n</think>"
                        } else {
                            finalContent = "<think>\n\(thinkingContent)\n</think>\n\n\(textContent)"
                        }
                    } else {
                        finalContent = textContent
                    }
                    return (finalContent, role, nil)
                }
            }
        }
        catch {
            WardenLog.app.error("Claude JSON parse error: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            return (false, nil, nil, nil, nil)
        }
        
        var isFinished = false
        var textContent = ""
        var parseError: Error?
        var role: String?
        
        guard let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            parseError = NSError(
                domain: "SSEParsing",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"]
            )
            return (isFinished, parseError, nil, nil, nil)
        }

        if let eventType = json["type"] as? String {
            switch eventType {
            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any] {
                    if let blockType = contentBlock["type"] as? String, blockType == "thinking" {
                        role = "reasoning"
                        textContent = (contentBlock["thinking"] as? String) ?? (contentBlock["text"] as? String) ?? ""
                    } else {
                        textContent = contentBlock["text"] as? String ?? ""
                    }
                }
            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    if let deltaType = delta["type"] as? String, deltaType == "thinking_delta" {
                        role = "reasoning"
                        textContent = delta["thinking"] as? String ?? ""
                    } else {
                        textContent = delta["text"] as? String ?? ""
                    }
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
        return (isFinished, parseError, textContent.isEmpty ? nil : textContent, role, nil)
    }
}
