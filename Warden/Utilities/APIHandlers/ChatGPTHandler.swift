import CoreData
import Foundation

private struct ChatGPTModelsResponse: Codable {
    let data: [ChatGPTModel]
}

private struct ChatGPTModel: Codable {
    let id: String
}

class ChatGPTHandler: BaseAPIHandler {
    internal let dataLoader = BackgroundDataLoader()

    override init(config: APIServiceConfiguration, session: URLSession) {
        super.init(config: config, session: session)
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

    override internal func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
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

            processedMessages.append(processedMessage)
        }

        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": processedMessages,
            "temperature": temperatureOverride,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }



    override internal func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
                print("Response: \(responseString)")
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
                        return (messageContent, messageRole)
                    }
                }
            }
            catch {
                print("Error parsing JSON: \(error.localizedDescription)")
                return nil
            }
        }
        return nil
    }

    override internal func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            print("No data received.")
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil)
        }

        let defaultRole = "assistant"
        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any] {
                if let choices = dict["choices"] as? [[String: Any]],
                    let firstChoice = choices.first,
                    let delta = firstChoice["delta"] as? [String: Any],
                    let contentPart = delta["content"] as? String
                {

                    let finished = false
                    if let finishReason = firstChoice["finish_reason"] as? String, finishReason == "stop" {
                        _ = true
                    }
                    return (finished, nil, contentPart, defaultRole)
                }
            }
        }
        catch {
            #if DEBUG
                print(String(data: data, encoding: .utf8) ?? "Data cannot be converted into String")
                print("Error parsing JSON: \(error)")
            #endif

            return (false, APIError.decodingFailed("Failed to parse JSON: \(error.localizedDescription)"), nil, nil)
        }

        return (false, nil, nil, nil)
    }


}
