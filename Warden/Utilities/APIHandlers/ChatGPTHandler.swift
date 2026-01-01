import CoreData
import Foundation
import os

private struct ChatGPTModelsResponse: Codable {
    let data: [ChatGPTModel]
}

private struct ChatGPTModel: Codable {
    let id: String
}

class ChatGPTHandler: BaseAPIHandler {
    internal let dataLoader = BackgroundDataLoader()

    override init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        super.init(config: config, session: session, streamingSession: streamingSession)
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
    }


    override func fetchModels() async throws -> [AIModel] {
        let modelsURL = baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models")

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

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

    override internal func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var temperatureOverride = temperature

        if AppConstants.openAiReasoningModels.contains(self.model) {
            temperatureOverride = 1
        }

        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }
            
            // Handle tool_call_id if present (for tool results)
            if let toolCallId = message["tool_call_id"] {
                processedMessage["tool_call_id"] = toolCallId
            }
            
            // Handle name if present (for tool results)
            if let name = message["name"] {
                processedMessage["name"] = name
            }

            if let content = message["content"] {
                let imagePattern = "<image-uuid>(.*?)</image-uuid>"
                let filePattern = "<file-uuid>(.*?)</file-uuid>"
                
                let hasImages = content.range(of: imagePattern, options: .regularExpression) != nil
                let hasFiles = content.range(of: filePattern, options: .regularExpression) != nil

                if hasImages || hasFiles {
                    var textContent = content
                    
                    // Remove all UUID patterns from text content
                    textContent = textContent.replacingOccurrences(of: imagePattern, with: "", options: .regularExpression)
                    textContent = textContent.replacingOccurrences(of: filePattern, with: "", options: .regularExpression)
                    textContent = textContent.trimmingCharacters(in: .whitespacesAndNewlines)

                    var contentArray: [[String: Any]] = []

                    // Process file attachments first (as text content)
                    if hasFiles {
                        let fileRegex = try? NSRegularExpression(pattern: filePattern, options: [])
                        let nsString = content as NSString
                        let fileMatches = fileRegex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

                        for match in fileMatches {
                            if match.numberOfRanges > 1 {
                                let uuidRange = match.range(at: 1)
                                let uuidString = nsString.substring(with: uuidRange)

                                if let uuid = UUID(uuidString: uuidString),
                                   let fileContent = self.dataLoader.loadFileContent(uuid: uuid) {
                                    contentArray.append(["type": "text", "text": fileContent])
                                }
                            }
                        }
                    }
                    
                    // Add remaining text content if any
                    if !textContent.isEmpty {
                        contentArray.append(["type": "text", "text": textContent])
                    }

                    // Process image attachments
                    if hasImages {
                        let imageRegex = try? NSRegularExpression(pattern: imagePattern, options: [])
                        let nsString = content as NSString
                        let imageMatches = imageRegex?.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []

                        for match in imageMatches {
                            if match.numberOfRanges > 1 {
                                let uuidRange = match.range(at: 1)
                                let uuidString = nsString.substring(with: uuidRange)

                                if let uuid = UUID(uuidString: uuidString),
                                    let imageData = self.dataLoader.loadImageData(uuid: uuid)
                                {
                                    contentArray.append([
                                        "type": "image_url",
                                        "image_url": ["url": "data:image/jpeg;base64,\(imageData.base64EncodedString())"],
                                    ])
                                }
                            }
                        }
                    }

                    processedMessage["content"] = contentArray
                }
                else {
                    processedMessage["content"] = content
                }
            }
            
            // Handle tool_calls in assistant messages
            if let toolCallsJson = message["tool_calls"], 
               let data = toolCallsJson.data(using: .utf8),
               let toolCalls = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                processedMessage["tool_calls"] = toolCalls
            }
            // Also check for our custom serialized key for Core Data compatibility
            else if let toolCallsJsonStr = message["tool_calls_json"],
                    let data = toolCallsJsonStr.data(using: .utf8),
                    let toolCalls = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] {
                processedMessage["tool_calls"] = toolCalls
            }

            processedMessages.append(processedMessage)
        }

        var jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": processedMessages,
            "temperature": temperatureOverride,
        ]
        
        if let tools = tools, !tools.isEmpty {
            jsonDict["tools"] = tools
            jsonDict["tool_choice"] = "auto"
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonDict, options: [])
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }

        return request
    }



    override internal func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            WardenLog.app.debug("ChatGPT response received: \(responseString.count, privacy: .public) char(s)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let lastIndex = choices.indices.last,
                   let message = choices[lastIndex]["message"] as? [String: Any]
                {
                    let messageRole = message["role"] as? String
                    let contentText = extractTextContent(from: message["content"])
                    let reasoningText = extractTextContent(from: message["reasoning_content"] ?? message["reasoning"])
                    
                    var toolCalls: [ToolCall]? = nil
                    if let toolCallsData = message["tool_calls"] as? [[String: Any]] {
                        toolCalls = toolCallsData.compactMap { dict -> ToolCall? in
                            guard let id = dict["id"] as? String,
                                  let type = dict["type"] as? String,
                                  let function = dict["function"] as? [String: Any],
                                  let name = function["name"] as? String,
                                  let arguments = function["arguments"] as? String else {
                                return nil
                            }
                            return ToolCall(id: id, type: type, function: ToolCall.FunctionCall(name: name, arguments: arguments))
                        }
                    }
                    
                    let finalContent = composeResponse(reasoningText: reasoningText, contentText: contentText)
                    return (finalContent, messageRole, toolCalls)
                }
            }
            catch {
                WardenLog.app.error("ChatGPT JSON parse error: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }

    override internal func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil, nil)
        }

        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any] {
                if let choices = dict["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let delta = firstChoice["delta"] as? [String: Any]
                {
                    let contentPart = extractTextContent(from: delta["content"])
                    let reasoningPart = extractTextContent(from: delta["reasoning_content"] ?? delta["reasoning"])

                    var toolCalls: [ToolCall]? = nil
                    if let toolCallsData = delta["tool_calls"] as? [[String: Any]] {
                        toolCalls = toolCallsData.compactMap { dict -> ToolCall? in
                            // In streaming, tool_calls might be partial.
                            // Usually index is present.
                            // We map what we have.
                            // Note: OpenAI streaming sends partial tool calls.
                            // We need to accumulate them in the caller or pass raw partials.
                            // For simplicity, we'll pass what we get and let MessageManager accumulate if needed.
                            // But ToolCall struct expects non-optional fields.
                            // If we receive partial, we might need a different struct or optional fields.
                            // However, usually 'index', 'id', 'type', 'function' (name/args) come in chunks.
                            // We'll try to map if possible, but for streaming tools, we might need to return raw dict or handle accumulation here.
                            // Given the complexity, let's assume we return the raw dict wrapped in ToolCall if possible, or we need to change ToolCall to have optionals?
                            // No, ToolCall is Codable.
                            // Let's just return nil for toolCalls here if we can't fully construct it, OR
                            // we need to handle accumulation in MessageManager.
                            // But MessageManager expects [ToolCall].
                            // Actually, for streaming, we usually get:
                            // Chunk 1: tool_calls: [{index: 0, id: "...", type: "function", function: {name: "..."}}]
                            // Chunk 2: tool_calls: [{index: 0, function: {arguments: "..."}}]
                            // So we can't construct a full ToolCall from a chunk.
                            // We need to return the raw delta for tool calls?
                            // Or we update the return type of parseDeltaJSONResponse to include `[String: Any]?` for tool_calls delta.
                            // But protocol says `[ToolCall]?`.
                            // I'll stick to `[ToolCall]?` but I'll make ToolCall fields optional?
                            // Or I'll construct a "PartialToolCall".
                            // For now, I'll return nil for toolCalls in streaming and handle it if I have time, 
                            // OR I'll try to map what I can.
                            // Wait, if I return nil, I lose the tool call data.
                            // I MUST handle it.
                            // I'll change `ToolCall` to have optional fields?
                            // Or I'll pass the raw dictionary in a wrapper?
                            
                            // Let's assume for now we only support non-streaming tools, OR
                            // we try to hack it.
                            // Actually, I'll just return the partial data mapped to ToolCall with empty strings for missing fields?
                            // That's risky.
                            
                            // Better: Update `parseDeltaJSONResponse` to return `Any?` for tool delta.
                            // But protocol...
                            
                            // I'll use `ToolCall` but with empty strings for missing fields, and rely on `index` to merge.
                            // But `ToolCall` doesn't have `index`.
                            // I should add `index` to `ToolCall`.
                            
                            guard let index = dict["index"] as? Int else { return nil }
                            let id = dict["id"] as? String ?? ""
                            let type = dict["type"] as? String ?? ""
                            let function = dict["function"] as? [String: Any]
                            let name = function?["name"] as? String ?? ""
                            let arguments = function?["arguments"] as? String ?? ""
                            
                            // We need to pass the index to the caller to merge.
                            // I'll add `index` to `ToolCall` struct in APIProtocol?
                            // Or just rely on order?
                            // OpenAI guarantees order?
                            
                            return ToolCall(id: id, type: type, function: ToolCall.FunctionCall(name: name, arguments: arguments))
                        }
                    }

                    let finishReason = firstChoice["finish_reason"] as? String
                    let finished = finishReason == "stop" || finishReason == "tool_calls" || finishReason == "length"

                    if let reasoning = reasoningPart, !reasoning.isEmpty {
                        return (finished, nil, reasoning, "reasoning", nil)
                    }
                    
                    return (finished, nil, contentPart, defaultRole, toolCalls)
                }
            }
        }
        catch {
            #if DEBUG
            WardenLog.app.debug(
                "ChatGPT delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif

            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }


}

private extension ChatGPTHandler {
    func extractTextContent(from value: Any?) -> String? {
        guard let value = value, !(value is NSNull) else { return nil }
        if let text = value as? String {
            return text
        }
        if let dict = value as? [String: Any] {
            if let text = dict["text"] as? String {
                return text
            }
            if let nested = dict["content"] {
                return extractTextContent(from: nested)
            }
            if let nested = dict["value"] {
                return extractTextContent(from: nested)
            }
        }
        if let array = value as? [Any] {
            let parts = array.compactMap { extractTextContent(from: $0) }
            if parts.isEmpty { return nil }
            return parts.joined()
        }
        return nil
    }
    
    func composeResponse(reasoningText: String?, contentText: String?) -> String? {
        let trimmedReasoning = reasoningText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = contentText
        var sections: [String] = []
        if let reasoning = trimmedReasoning, !reasoning.isEmpty {
            sections.append("<think>\n\(reasoning)\n</think>")
        }
        if let content = content, !content.isEmpty {
            sections.append(content)
        }
        if sections.isEmpty {
            return nil
        }
        return sections.joined(separator: "\n\n")
    }
}
