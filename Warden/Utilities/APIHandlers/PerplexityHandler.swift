

class PerplexityHandler: APIService {
    let name: String
    let baseURL: URL
    private let apiKey: String
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
                        if line.data(using: .utf8) != nil {
                            let prefix = "data: "
                            var index = line.startIndex
                            if line.starts(with: prefix) {
                                index = line.index(line.startIndex, offsetBy: prefix.count)
                            }
                            let jsonData = String(line[index...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            if let jsonData = jsonData.data(using: .utf8) {
                                let (finished, error, messageData, messageRole) = parseDeltaJSONResponse(data: jsonData)

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

    func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool)
        -> URLRequest
    {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

    func parseJSONResponse(data: Data) -> (String, String)? {
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
                        let citations = dict["citations"] as? [String]
                        let finalContent = formatContentWithCitations(messageContent, citations: citations)
                        return (finalContent, messageRole)
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

    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
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
                    let finished = firstChoice["finish_reason"] as? String == "stop"
                    let citations = dict["citations"] as? [String]
                    let finalContent = formatContentWithCitations(contentPart, citations: citations)
                    return (finished, nil, finalContent, defaultRole)
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
