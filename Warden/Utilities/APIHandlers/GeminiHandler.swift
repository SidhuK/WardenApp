
import Foundation

private struct ModelResponse: Codable {
    let models: [Model]
}

private struct Model: Codable {
    let name: String
    
    var id: String {
        name.replacingOccurrences(of: "models/", with: "")
    }
}

class GeminiHandler: ChatGPTHandler {
    override internal func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        attachmentPolicy: AttachmentPolicy,
        stream: Bool
    ) async throws -> URLRequest {
        var request = try await super.prepareRequest(
            requestMessages: requestMessages,
            tools: tools,
            model: model,
            settings: settings,
            attachmentPolicy: attachmentPolicy,
            stream: stream
        )

        guard settings.reasoningEffort == .off,
              let body = request.httpBody,
              var json = try? JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        else {
            return request
        }

        // Gemini uses model defaults when reasoning configuration is omitted.
        // Avoid serializing an explicit "off" value through the OpenAI-compatible path.
        json.removeValue(forKey: "reasoning_effort")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: json, options: [])
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }

        return request
    }

    override func fetchModels() async throws -> [AIModel] {
        var urlComponents = URLComponents(url: baseURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("models"), resolvingAgainstBaseURL: true)
        urlComponents?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        
        guard let modelsURL = urlComponents?.url else {
            throw APIError.unknown("Invalid URL")
        }

        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await session.data(for: request)

            let result = handleAPIResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                guard let responseData = responseData else {
                    throw APIError.invalidResponse
                }

                let geminiResponse = try JSONDecoder().decode(ModelResponse.self, from: responseData)
                return geminiResponse.models.map { AIModel(id: $0.id) }

            case .failure(let error):
                throw error
            }
        }
        catch {
            throw APIError.requestFailed(error)
        }
    }
}
