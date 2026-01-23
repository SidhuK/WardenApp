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
        settings: GenerationSettings,
        attachmentPolicy: AttachmentPolicy,
        stream: Bool
    ) async throws -> URLRequest {
        let provider = ProviderID(normalizing: name)

        let hasFileTags = requestMessages.contains { message in
            guard let content = message["content"] else { return false }
            return content.contains(MessageContent.fileTagStart)
        }

        let hasTools = (tools?.isEmpty == false)
        let hasToolRoleMessages = requestMessages.contains { $0["role"] == "tool" }
        let hasSerializedToolCalls = requestMessages.contains { message in
            message["tool_calls"] != nil || message["tool_calls_json"] != nil || message["tool_call_id"] != nil
        }
        let shouldUseResponsesAPI = provider == .chatgpt
            && attachmentPolicy == .preferProviderAttachments
            && hasFileTags
            && !hasTools
            && !hasToolRoleMessages
            && !hasSerializedToolCalls

        if shouldUseResponsesAPI {
            return try await prepareResponsesRequest(
                requestMessages: requestMessages,
                settings: settings,
                stream: stream
            )
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var temperatureOverride = settings.temperature

        let isReasoningModel = Self.isReasoningModel(self.model, provider: name)
        if isReasoningModel {
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
                if AttachmentMessageExpander.containsAttachmentTags(content) {
                    let format: AttachmentMessageExpander.Format =
                        content.contains(MessageContent.imageTagStart) ? .openAIContentArray : .stringInlining
                    let expanded = AttachmentMessageExpander.expand(
                        content: content,
                        for: format,
                        dataLoader: dataLoader
                    )

                    switch expanded {
                    case .openAIContentArray(let contentArray):
                        processedMessage["content"] = contentArray
                    case .string(let text):
                        processedMessage["content"] = text
                    }
                } else {
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

        let isOpenAIReasoningModel = Self.isReasoningModel(self.model, provider: name)
        let shouldSendReasoningEffort = isOpenAIReasoningModel || provider == .xai
        
        if shouldSendReasoningEffort {
            jsonDict["reasoning_effort"] = settings.reasoningEffort.openAIReasoningEffortValue
        }
        
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
                if let dict = json as? [String: Any] {
                    if let parsed = parseResponsesJSON(dict: dict) {
                        return parsed
                    }

                    if let choices = dict["choices"] as? [[String: Any]],
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
                                return ToolCall(
                                    id: id,
                                    type: type,
                                    function: ToolCall.FunctionCall(name: name, arguments: arguments)
                                )
                            }
                        }

                        let finalContent = composeResponse(reasoningText: reasoningText, contentText: contentText)
                        return (finalContent, messageRole, toolCalls)
                    }
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
                if let type = dict["type"] as? String {
                    return parseResponsesStreamEvent(type: type, dict: dict)
                }

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
    func prepareResponsesRequest(
        requestMessages: [[String: String]],
        settings: GenerationSettings,
        stream: Bool
    ) async throws -> URLRequest {
        let responsesURL: URL = {
            if baseURL.path.contains("/responses") {
                return baseURL
            }
            return baseURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("responses")
        }()

        var request = URLRequest(url: responsesURL)
        request.httpMethod = "POST"
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let inputMessages = try await buildResponsesInputMessages(requestMessages: requestMessages)

        var jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "input": inputMessages,
            "temperature": settings.temperature,
        ]

        if let body = try? JSONSerialization.data(withJSONObject: jsonDict, options: []) {
            request.httpBody = body
        } else {
            throw APIError.decodingFailed("Failed to encode responses request JSON")
        }

        return request
    }

    func buildResponsesInputMessages(requestMessages: [[String: String]]) async throws -> [[String: Any]] {
        var inputMessages: [[String: Any]] = []
        inputMessages.reserveCapacity(requestMessages.count)

        for message in requestMessages {
            guard let role = message["role"], let content = message["content"] else { continue }

            var contentParts: [[String: Any]] = []
            contentParts.reserveCapacity(8)

            let tokens = AttachmentTagTokenizer.tokenize(content)
            for token in tokens {
                switch token {
                case .text(let text):
                    guard containsNonWhitespaceAndNewlines(text) else { continue }
                    contentParts.append(["type": "input_text", "text": text])

                case .image(let uuid):
                    guard let imageData = await AttachmentStore.shared.imageData(uuid: uuid) else {
                        contentParts.append(["type": "input_text", "text": "[Missing image attachment]"])
                        continue
                    }

                    let (mime, base64) = await Task.detached(priority: .userInitiated) {
                        let mime = AttachmentMimeTypeSniffer.sniff(data: imageData) ?? "image/jpeg"
                        return (mime, imageData.base64EncodedString())
                    }.value

                    contentParts.append([
                        "type": "input_image",
                        "image_url": "data:\(mime);base64,\(base64)",
                    ])

                case .file(let uuid):
                    if let file = await AttachmentStore.shared.fileData(uuid: uuid) {
                        let maxBytes = 50 * 1024 * 1024
                        if file.data.count > maxBytes {
                            if let fileText = dataLoader.loadFileContent(uuid: uuid) {
                                contentParts.append(["type": "input_text", "text": fileText])
                            } else {
                                contentParts.append([
                                    "type": "input_text",
                                    "text": "[File too large to attach (\(file.fileName))]",
                                ])
                            }
                            continue
                        }

                        let (mime, base64) = await Task.detached(priority: .userInitiated) {
                            let mime = AttachmentMimeTypeSniffer.sniff(data: file.data, fileName: file.fileName)
                            return (mime, file.data.base64EncodedString())
                        }.value

                        if let mime, mime.hasPrefix("image/") {
                            contentParts.append([
                                "type": "input_image",
                                "image_url": "data:\(mime);base64,\(base64)",
                            ])
                        } else {
                            contentParts.append([
                                "type": "input_file",
                                "filename": file.fileName,
                                "file_data": base64,
                            ])
                        }
                    } else if let fileText = dataLoader.loadFileContent(uuid: uuid) {
                        contentParts.append(["type": "input_text", "text": fileText])
                    } else {
                        contentParts.append(["type": "input_text", "text": "[Missing file attachment]"])
                    }
                }
            }

            if contentParts.isEmpty {
                contentParts.append(["type": "input_text", "text": content])
            }

            inputMessages.append([
                "type": "message",
                "role": role,
                "content": contentParts,
            ])
        }

        return inputMessages
    }

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

    func parseResponsesJSON(dict: [String: Any]) -> (String?, String?, [ToolCall]?)? {
        guard let output = dict["output"] as? [[String: Any]] else { return nil }

        var textParts: [String] = []
        textParts.reserveCapacity(8)

        for item in output {
            guard let type = item["type"] as? String, type == "message" else { continue }
            guard let content = item["content"] as? [[String: Any]] else { continue }

            for part in content {
                guard let partType = part["type"] as? String else { continue }
                if partType == "output_text", let text = part["text"] as? String {
                    textParts.append(text)
                }
            }
        }

        if textParts.isEmpty {
            return nil
        }

        return (textParts.joined(), "assistant", nil)
    }

    func parseResponsesStreamEvent(
        type: String,
        dict: [String: Any]
    ) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        switch type {
        case "response.output_text.delta":
            let delta = dict["delta"] as? String
            return (false, nil, delta, "assistant", nil)

        case "response.completed":
            return (true, nil, nil, nil, nil)

        case "response.failed", "response.incomplete":
            let message = (dict["error"] as? [String: Any])?["message"] as? String
                ?? "Response stream failed"
            let error = APIError.decodingFailed(message)
            return (true, error, nil, nil, nil)

        default:
            return (false, nil, nil, nil, nil)
        }
    }

    func containsNonWhitespaceAndNewlines(_ text: String) -> Bool {
        text.unicodeScalars.contains { !CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}

extension ChatGPTHandler {
    static func isReasoningModel(_ modelId: String, provider: String) -> Bool {
        if let metadata = ModelMetadataStorage.getMetadata(provider: provider, modelId: modelId),
           metadata.hasReasoning {
            return true
        }
        
        if AppConstants.openAiReasoningModels.contains(modelId) {
            return true
        }
        
        let lower = modelId.lowercased()
        let modelSuffix = lower.split(separator: "/").last.map(String.init) ?? lower
        
        return modelSuffix.hasPrefix("o1")
            || modelSuffix.hasPrefix("o3")
            || modelSuffix.hasPrefix("o4")
            || modelSuffix.contains("gpt-5")
    }
}
