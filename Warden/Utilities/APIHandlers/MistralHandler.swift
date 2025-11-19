import Foundation
import CoreData

private struct MistralModelsResponse: Codable {
    let data: [MistralModel]
}

private struct MistralModel: Codable {
    let id: String
}

class MistralHandler: APIService {
    let name: String
    let baseURL: URL
    internal let apiKey: String
    let model: String
    let session: URLSession

    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
    }

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        defaultSendMessage(requestMessages, temperature: temperature, completion: completion)
    }

    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                model: model,
                temperature: temperature,
                stream: true
            )

            Task {
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

                    for try await line in stream.lines {
                        if line.data(using: .utf8) != nil && isNotSSEComment(line) {
                            let prefix = "data: "
                            var index = line.startIndex
                            if line.starts(with: prefix) {
                                index = line.index(line.startIndex, offsetBy: prefix.count)
                            }
                            let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonData.data(using: .utf8) {
                                let (finished, error, messageData, _) = parseDeltaJSONResponse(data: jsonData)

                                if error != nil {
                                    continuation.finish(throwing: error)
                                }
                                else {
                                    if messageData != nil {
                                        continuation.yield(messageData!)
                                    }
                                    if finished {
                                        continuation.finish()
                                    }
                                }
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

    func fetchModels() async throws -> [AIModel] {
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

                let mistralResponse = try JSONDecoder().decode(MistralModelsResponse.self, from: responseData)

                return mistralResponse.data.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }

    func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Convert the messages array to proper format
        var processedMessages: [[String: Any]] = []

        for message in requestMessages {
            var processedMessage: [String: Any] = [:]

            if let role = message["role"] {
                processedMessage["role"] = role
            }

            if let content = message["content"] {
                processedMessage["content"] = content
            }

            processedMessages.append(processedMessage)
        }

        let parameters: [String: Any] = [
            "model": model,
            "messages": processedMessages,
            "temperature": temperature,
            "stream": stream
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        } catch {
            print("Error creating request body: \(error)")
        }

        return request
    }



    private func parseJSONResponse(data: Data) -> (String?, Float?)? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String
            {
                var usageTokens: Float?
                if let usage = json["usage"] as? [String: Any],
                   let totalTokens = usage["total_tokens"] as? Int
                {
                    usageTokens = Float(totalTokens)
                }
                return (content, usageTokens)
            }
        } catch {
            print("Error parsing JSON response: \(error)")
        }
        return nil
    }

    private func parseDeltaJSONResponse(data: Data) -> (Bool, Error?, String?, Float?) {
        do {
            // Check for [DONE] message
            if let string = String(data: data, encoding: .utf8), string == "[DONE]" {
                return (true, nil, nil, nil)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                var usageTokens: Float?
                if let usage = json["usage"] as? [String: Any],
                   let totalTokens = usage["total_tokens"] as? Int
                {
                    usageTokens = Float(totalTokens)
                }
                
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first
                {
                    if let delta = firstChoice["delta"] as? [String: Any],
                       let content = delta["content"] as? String
                    {
                        return (false, nil, content, usageTokens)
                    }
                    
                    // If there's a finish_reason, we're done
                    if let finishReason = firstChoice["finish_reason"] as? String, !finishReason.isEmpty {
                        return (true, nil, nil, usageTokens)
                    }
                }
            }
        } catch {
            return (false, error, nil, nil)
        }
        return (false, nil, nil, nil)
    }
    
}
