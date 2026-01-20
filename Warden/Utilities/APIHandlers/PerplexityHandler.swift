import Foundation
import os

class PerplexityHandler: BaseAPIHandler {

    override func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": requestMessages,
            "temperature": settings.temperature,
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

    private func formatContentWithCitations(_ content: String, citations: [String]?) -> String {
        var formattedContent = content
        if formattedContent.contains("["), let citations = citations {
            for (index, citation) in citations.enumerated() {
                let reference = "[\(index + 1)]"
                formattedContent = formattedContent.replacingOccurrences(
                    of: reference,
                    with: "[\\[\(index + 1)\\]](\(citation))"
                )
            }
        }
        return formattedContent
    }

    override func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
            WardenLog.app.debug("Perplexity response received: \(responseString.count, privacy: .public) char(s)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    if let choices = dict["choices"] as? [[String: Any]],
                        let lastIndex = choices.indices.last,
                        let content = choices[lastIndex]["message"] as? [String: Any],
                        let messageRole = content["role"] as? String,
                        let messageContent = content["content"] as? String
                    {
                        let citations = dict["citations"] as? [String]
                        let finalContent = formatContentWithCitations(messageContent, citations: citations)
                        return (finalContent, messageRole, nil)
                    }
                }
            }
            catch {
                WardenLog.app.error("Perplexity JSON parse error: \(error.localizedDescription, privacy: .public)")
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

            if let dict = jsonResponse as? [String: Any] {
                if let choices = dict["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let delta = firstChoice["delta"] as? [String: Any],
                    let contentPart = delta["content"] as? String
                {
                    let finished = firstChoice["finish_reason"] as? String == "stop"
                    let citations = dict["citations"] as? [String]
                    let finalContent = formatContentWithCitations(contentPart, citations: citations)
                    return (finished, nil, finalContent, defaultRole, nil)
                }
            }
        }
        catch {
            #if DEBUG
            WardenLog.app.debug(
                "Perplexity delta JSON parse error: \(error.localizedDescription, privacy: .public) (\(data.count, privacy: .public) byte(s))"
            )
            #endif

            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil, nil)
        }

        return (false, nil, nil, nil, nil)
    }
}
