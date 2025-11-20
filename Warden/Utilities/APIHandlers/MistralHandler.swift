import Foundation
import CoreData

private struct MistralModelsResponse: Codable {
    let data: [MistralModel]
}

private struct MistralModel: Codable {
    let id: String
}

class MistralHandler: BaseAPIHandler {
    
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

    override func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool) -> URLRequest {
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

    override func parseJSONResponse(data: Data) -> (String, String)? {
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String
            {
                // Note: Usage tokens are currently ignored by BaseAPIHandler signature
                return (content, "assistant")
            }
        } catch {
            print("Error parsing JSON response: \(error)")
        }
        return nil
    }

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else { return (false, nil, nil, nil) }
        
        do {
            // Check for [DONE] message
            if let string = String(data: data, encoding: .utf8), string == "[DONE]" {
                return (true, nil, nil, nil)
            }

            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first
                {
                    if let delta = firstChoice["delta"] as? [String: Any],
                       let content = delta["content"] as? String
                    {
                        return (false, nil, content, "assistant")
                    }
                    
                    // If there's a finish_reason, we're done
                    if let finishReason = firstChoice["finish_reason"] as? String, !finishReason.isEmpty {
                        return (true, nil, nil, nil)
                    }
                }
            }
        } catch {
            return (false, error, nil, nil)
        }
        return (false, nil, nil, nil)
    }
}
