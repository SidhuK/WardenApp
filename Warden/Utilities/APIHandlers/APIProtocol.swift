
import Foundation

enum APIError: Error {
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(String)
    case unauthorized
    case rateLimited
    case serverError(String)
    case unknown(String)
    case noApiService(String)
}

protocol APIService {
    var name: String { get }
    var baseURL: URL { get }
    var session: URLSession { get }
    var model: String { get }

    func sendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    )
    
    func sendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws
        -> AsyncThrowingStream<String, Error>
    
    func fetchModels() async throws -> [AIModel]
    
    func prepareRequest(requestMessages: [[String: String]], model: String, temperature: Float, stream: Bool) -> URLRequest
}

protocol APIServiceConfiguration {
    var name: String { get set }
    var apiUrl: URL { get set }
    var apiKey: String { get set }
    var model: String { get set }
}

struct AIModel: Codable, Identifiable {
    let id: String
    
    init(id: String) {
        self.id = id
    }
}

// MARK: - Default Implementations for Common API Patterns

extension APIService {
    func fetchModels() async throws -> [AIModel] {
        return []
    }

    /// Default implementation of API response handling with standard HTTP status code mapping
    /// Handlers can override this if they need specialized behavior
    func handleAPIResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data?, APIError> {
        if let error = error {
            return .failure(.requestFailed(error))
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }

        if !(200...299).contains(httpResponse.statusCode) {
            if let data = data, let errorResponse = String(data: data, encoding: .utf8) {
                switch httpResponse.statusCode {
                case 401:
                    return .failure(.unauthorized)
                case 429:
                    return .failure(.rateLimited)
                case 400...499:
                    return .failure(.serverError("Client Error: \(errorResponse)"))
                case 500...599:
                    return .failure(.serverError("Server Error: \(errorResponse)"))
                default:
                    return .failure(.unknown("Unknown error: \(errorResponse)"))
                }
            } else {
                return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
            }
        }

        return .success(data)
    }

    /// Default implementation of SSE comment checking
    func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }

    /// Hook method for handler-specific parsing of JSON responses
    /// Handlers should override this to extract content based on their API format
    /// Default returns nil - handlers must implement
    func parseJSONResponse(data: Data) -> (String, String)? {
        return nil  // Handlers must override
    }

    /// Hook method for handler-specific parsing of SSE delta responses
    /// Handlers should override this based on their streaming JSON format
    /// Returns: (isDone, error, content, role)
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?) {
        return (false, nil, nil, nil)  // Handlers must override
    }

    /// Hook method for preparing stream requests
    /// Handlers can override if they need custom stream request building
    func prepareStreamRequest(_ requestMessages: [[String: String]], model: String, temperature: Float) -> URLRequest {
        return prepareRequest(requestMessages: requestMessages, model: model, temperature: temperature, stream: true)
    }

    /// Generic streaming implementation - consolidates shared SSE handling logic
    /// Handlers only need to override parseDeltaJSONResponse for their specific format
    /// The default implementation provided in sendMessageStream handles all other logic
    func defaultSendMessageStream(_ requestMessages: [[String: String]], temperature: Float) async throws -> AsyncThrowingStream<String, Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareStreamRequest(requestMessages, model: model, temperature: temperature)

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

                                if let error = error {
                                    continuation.finish(throwing: error)
                                    return
                                } else if let messageData = messageData {
                                    continuation.yield(messageData)
                                }

                                if finished {
                                    continuation.finish()
                                    return
                                }
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Default implementation of non-streaming message sending
    /// Consolidates shared request/response handling across all handlers
    /// Handlers only need to override parseJSONResponse for their specific format
    func defaultSendMessage(
        _ requestMessages: [[String: String]],
        temperature: Float,
        completion: @escaping (Result<String, APIError>) -> Void
    ) {
        let request = prepareRequest(
            requestMessages: requestMessages,
            model: model,
            temperature: temperature,
            stream: false
        )

        session.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                let result = self.handleAPIResponse(response, data: data, error: error)

                switch result {
                case .success(let responseData):
                    if let responseData = responseData {
                        guard let (messageContent, _) = self.parseJSONResponse(data: responseData) else {
                            completion(.failure(.decodingFailed("Failed to parse response")))
                            return
                        }
                        completion(.success(messageContent))
                    } else {
                        completion(.failure(.invalidResponse))
                    }

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }
}
