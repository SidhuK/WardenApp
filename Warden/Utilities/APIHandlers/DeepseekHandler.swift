import Foundation

private struct DeepseekModelsResponse: Codable {
    let data: [DeepseekModel]
}

private struct DeepseekModel: Codable {
    let id: String
}

class DeepseekHandler: ChatGPTHandler {
    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
                print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let lastIndex = choices.indices.last,
                   let message = choices[lastIndex]["message"] as? [String: Any],
                   let messageRole = message["role"] as? String,
                   let messageContent = message["content"] as? String
                {
                    var finalContent = messageContent
                    
                    // Handle reasoning content if available
                    if let reasoningContent = message["reasoning_content"] as? String {
                        finalContent = "<think>\n\(reasoningContent)\n</think>\n\n\(messageContent)"
                    }
                    
                    return (finalContent, messageRole, nil)
                }
            } catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }
    
    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        guard let data = data else {
            print("No data received.")
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil, nil)
        }

        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any],
               let choices = dict["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let delta = firstChoice["delta"] as? [String: Any]
            {
                var content: String?
                var reasoningContent: String?
                
                if let contentPart = delta["content"] as? String {
                    content = contentPart
                }
                
                if let reasoningPart = delta["reasoning_content"] as? String {
                    reasoningContent = reasoningPart
                }
                
                let finished = firstChoice["finish_reason"] as? String == "stop"
                
                if let reasoningContent = reasoningContent {
                    return (finished, nil, reasoningContent, "reasoning", nil)
                } else if let content = content {
                    return (finished, nil, content, defaultRole, nil)
                }
            }
        } catch {
            #if DEBUG
                print(String(data: data, encoding: .utf8) ?? "Data cannot be converted into String")
                print("Error parsing JSON: \(error)")
            #endif
            
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }
    
    override func sendMessageStream(_ requestMessages: [[String: String]], tools: [[String: Any]]?, temperature: Float) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                tools: tools,
                model: model,
                temperature: temperature,
                stream: true
            )

            Task {
                var isInReasoningBlock = false
                
                do {
                    let (stream, response) = try await session.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)
                    switch result {
                    case .failure(let error):
                        var data = Data()
                        for try await byte in stream {
                            data.append(byte)
                        }
                        let error = APIError.serverError(
                            String(data: data, encoding: .utf8) ?? error.localizedDescription
                        )
                        continuation.finish(throwing: error)
                        return
                    case .success:
                        break
                    }

                    try await SSEStreamParser.parse(stream: stream) { [weak self] dataString in
                        guard let self = self else { return }
                        
                        if let jsonData = dataString.data(using: .utf8) {
                            let (finished, error, messageData, role, _) = self.parseDeltaJSONResponse(data: jsonData)

                            if let error = error {
                                throw error
                            } else if let messageData = messageData {
                                if role == "reasoning" {
                                    if !isInReasoningBlock {
                                        isInReasoningBlock = true
                                        continuation.yield(("<think>\n", nil))
                                    }
                                    continuation.yield((messageData, nil))
                                } else {
                                    if isInReasoningBlock {
                                        isInReasoningBlock = false
                                        continuation.yield(("\n</think>\n\n", nil))
                                    }
                                    continuation.yield((messageData, nil))
                                }
                            }
                            
                            if finished {
                                if isInReasoningBlock {
                                    continuation.yield(("\n</think>\n\n", nil))
                                }
                                continuation.finish()
                                return
                            }
                        }
                    }
                    continuation.finish()
                }
                catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    override func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) -> URLRequest {
        let filteredMessages = requestMessages.map { message -> [String: String] in
            var newMessage = message
            if let content = message["content"] {
                newMessage["content"] = removeThinkingTags(from: content)
            }
            return newMessage
        }
        
        return super.prepareRequest(requestMessages: filteredMessages, tools: tools, model: model, temperature: temperature, stream: stream)
    }
    
    private func removeThinkingTags(from content: String) -> String {
        let pattern = "<think>\\s*([\\s\\S]*?)\\s*</think>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(content.startIndex..., in: content)
            let modifiedString = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            
            return modifiedString.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            print("Error creating regex: \(error.localizedDescription)")
            return content
        }
    }
}
