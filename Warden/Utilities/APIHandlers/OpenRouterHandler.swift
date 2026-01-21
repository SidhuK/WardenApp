import Foundation
import os

class OpenRouterHandler: ChatGPTHandler {
    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            WardenLog.app.debug("OpenRouter response received: \(responseString.count, privacy: .public) char(s)")
            #endif
            
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any],
                   let choices = dict["choices"] as? [[String: Any]],
                   let lastIndex = choices.indices.last,
                   let message = choices[lastIndex]["message"] as? [String: Any],
                   let messageRole = message["role"] as? String
                {
                    let messageContent = message["content"] as? String
                    var finalContent = messageContent ?? ""
                    
                    let reasoningText = extractReasoningContent(from: message)
                    
                    if let reasoning = reasoningText, !reasoning.isEmpty {
                        if finalContent.isEmpty {
                            finalContent = "<think>\n\(reasoning)\n</think>"
                        } else {
                            finalContent = "<think>\n\(reasoning)\n</think>\n\n\(finalContent)"
                        }
                    }
                    
                    if messageContent == nil && reasoningText == nil {
                        #if DEBUG
                        WardenLog.app.debug("OpenRouter response missing both content and reasoning")
                        #endif
                        return nil
                    }
                    
                    return (finalContent, messageRole, nil)
                } else {
                    #if DEBUG
                    if let dict = json as? [String: Any] {
                        WardenLog.app.debug(
                            "OpenRouter parsing failed: structure mismatch. Keys: \(dict.keys.joined(separator: ", "), privacy: .public)"
                        )
                    } else {
                        WardenLog.app.debug("OpenRouter parsing failed: response is not a dictionary")
                    }
                    #endif
                }
            } catch {
                WardenLog.app.error("OpenRouter JSON parse error: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }
        return nil
    }
    
    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
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
                
                reasoningContent = extractStreamingReasoningContent(from: delta)
                
                let finished = firstChoice["finish_reason"] as? String == "stop"
                
                if let reasoningContent = reasoningContent, !reasoningContent.isEmpty {
                    return (finished, nil, reasoningContent, "reasoning", nil)
                } else if let content = content {
                    return (finished, nil, content, defaultRole, nil)
                }
            }
        } catch {
            #if DEBUG
            WardenLog.app.debug(
                "OpenRouter delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif
            
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }

    override internal func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        stream: Bool
    ) throws -> URLRequest {
        let filteredMessages = requestMessages.map { message -> [String: String] in
            var newMessage = message
            if let content = message["content"] {
                newMessage["content"] = removeThinkingTags(from: content)
            }
            return newMessage
        }
        
        var request = try super.prepareRequest(
            requestMessages: filteredMessages,
            tools: tools,
            model: model,
            settings: settings,
            stream: stream
        )

        if let body = request.httpBody,
           var json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any] {
            
            json.removeValue(forKey: "reasoning_effort")
            
            if settings.reasoningEffort != .off {
                let reasoningConfig = buildReasoningConfig(for: self.model, effort: settings.reasoningEffort)
                json["reasoning"] = reasoningConfig
            }
            
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])
            } catch {
                throw APIError.decodingFailed(error.localizedDescription)
            }
        }
        
        request.setValue("https://github.com/SidhuK/WardenApp", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Warden", forHTTPHeaderField: "X-Title")
        
        return request
    }
    
    private func removeThinkingTags(from content: String) -> String {
        let pattern = "<think>\\s*([\\s\\S]*?)\\s*</think>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(content.startIndex..., in: content)
            let modifiedString = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            
            return modifiedString.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            WardenLog.app.error("OpenRouter regex creation error: \(error.localizedDescription, privacy: .public)")
            return content
        }
    }
    
    private func extractReasoningContent(from message: [String: Any]) -> String? {
        return extractReasoning(from: message, joinSeparator: "\n")
    }
    
    private func extractStreamingReasoningContent(from delta: [String: Any]) -> String? {
        return extractReasoning(from: delta, joinSeparator: "")
    }
    
    private func buildReasoningConfig(for modelId: String, effort: ReasoningEffort) -> [String: Any] {
        if let metadata = ModelMetadataStorage.getMetadata(provider: "openrouter", modelId: modelId),
           let params = metadata.supportedParameters {
            if params.contains("reasoning.max_tokens") && !params.contains("reasoning.effort") {
                if let maxTokens = effort.openRouterMaxTokens {
                    return ["max_tokens": maxTokens]
                }
            }
        }
        
        let lower = modelId.lowercased()
        let usesMaxTokens = lower.contains("anthropic/") || lower.contains("claude")
            || lower.contains("google/") || lower.contains("gemini")
            || lower.contains("qwen")
        
        if usesMaxTokens, let maxTokens = effort.openRouterMaxTokens {
            return ["max_tokens": maxTokens]
        }
        
        return ["effort": effort.openRouterReasoningEffortValue]
    }
    
    private func extractReasoning(from dict: [String: Any], joinSeparator: String) -> String? {
        if let reasoningDetails = dict["reasoning_details"] as? [[String: Any]] {
            let texts = reasoningDetails.compactMap { detail -> String? in
                guard let type = detail["type"] as? String else { return nil }
                
                switch type {
                case "reasoning.text":
                    return detail["text"] as? String
                case "reasoning.summary":
                    return detail["summary"] as? String
                default:
                    return nil
                }
            }
            if !texts.isEmpty {
                return texts.joined(separator: joinSeparator)
            }
        }
        
        if let reasoning = dict["reasoning"] as? String {
            return reasoning
        }
        
        if let reasoningContent = dict["reasoning_content"] as? String {
            return reasoningContent
        }
        
        return nil
    }
}
