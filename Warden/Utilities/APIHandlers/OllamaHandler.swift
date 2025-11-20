
import Foundation

private struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

private struct OllamaModel: Codable {
    let name: String
}

class OllamaHandler: BaseAPIHandler {
    
    override func fetchModels() async throws -> [AIModel] {
        let tagsURL = baseURL.deletingLastPathComponent().appendingPathComponent("tags")
        
        var request = URLRequest(url: tagsURL)
        request.httpMethod = "GET"
        
        do {
            let (data, response) = try await session.data(for: request)
            
            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }
                
                let ollamaResponse = try JSONDecoder().decode(OllamaModelsResponse.self, from: responseData)
                
                return ollamaResponse.models.map { AIModel(id: $0.name) }
                
            case .failure(let error):
                throw error
            }
        } catch {
            throw APIError.requestFailed(error)
        }
    }

    override func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool) -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let jsonDict: [String: Any] = [
            "model": self.model,
            "stream": stream,
            "messages": requestMessages,
            "temperature": temperature,
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: jsonDict, options: [])

        return request
    }

    override func parseJSONResponse(data: Data) -> (String, String)? {
        if let responseString = String(data: data, encoding: .utf8) {
            #if DEBUG
                print("Response: \(responseString)")
            #endif
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: [])
                if let dict = json as? [String: Any] {
                    if let message = dict["message"] as? [String: Any],
                        let messageRole = message["role"] as? String,
                        let messageContent = message["content"] as? String
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

    override func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        guard let data = data else {
            print("No data received.")
            return (true, APIError.decodingFailed("No data received in SSE event"), nil, nil)
        }

        let dataString = String(data: data, encoding: .utf8)
        if dataString == "[DONE]" {
            return (true, nil, nil, nil)
        }

        do {
            let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])

            if let dict = jsonResponse as? [String: Any] {
                if let message = dict["message"] as? [String: Any],
                    let messageRole = message["role"] as? String,
                    let done = dict["done"] as? Bool,
                    let messageContent = message["content"] as? String
                {
                    return (done, nil, messageContent, messageRole)
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
