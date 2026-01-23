import Foundation
import os

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
            WardenLog.app.debug("Deepseek response received: \(responseString.count, privacy: .public) char(s)")
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
                WardenLog.app.error("Deepseek JSON parse error: \(error.localizedDescription, privacy: .public)")
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
            WardenLog.app.debug(
                "Deepseek delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif
            
            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }
    
    override func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        attachmentPolicy: AttachmentPolicy,
        stream: Bool
    ) async throws -> URLRequest {
        let filteredMessages = requestMessages.map { message -> [String: String] in
            var newMessage = message
            if let content = message["content"] {
                newMessage["content"] = removeThinkingTags(from: content)
            }
            return newMessage
        }
        
        return try await super.prepareRequest(
            requestMessages: filteredMessages,
            tools: tools,
            model: model,
            settings: settings,
            attachmentPolicy: attachmentPolicy,
            stream: stream
        )
    }
    
    private func removeThinkingTags(from content: String) -> String {
        let pattern = "<think>\\s*([\\s\\S]*?)\\s*</think>"
        
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: [])
            let range = NSRange(content.startIndex..., in: content)
            let modifiedString = regex.stringByReplacingMatches(in: content, options: [], range: range, withTemplate: "")
            
            return modifiedString.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            WardenLog.app.error("Deepseek regex creation error: \(error.localizedDescription, privacy: .public)")
            return content
        }
    }
}
