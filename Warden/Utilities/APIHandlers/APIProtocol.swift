
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

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: FunctionCall
    
    struct FunctionCall: Codable {
        let name: String
        let arguments: String
    }
}

protocol APIService {
    var name: String { get }
    var baseURL: URL { get }
    var session: URLSession { get }
    var model: String { get }

    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    )
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error>
    
    func fetchModels() async throws -> [AIModel]
    
    func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) -> URLRequest
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)?
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?)
}

// Default implementations
extension APIService {
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        // Default implementation ignores tools if not supported by specific handler
        // But we need to update the signature match.
        // This default implementation calls the OLD sendMessage? No, we are replacing it.
        // We need to implement the default logic here.
        
        let request = prepareRequest(
            requestMessages: requestMessages,
            tools: tools,
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
                        guard let (messageContent, _, toolCalls) = self.parseJSONResponse(data: responseData) else {
                            completion(.failure(.decodingFailed("Failed to parse response")))
                            return
                        }
                        completion(.success((messageContent, toolCalls)))
                    } else {
                        completion(.failure(.invalidResponse))
                    }

                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(requestMessages: requestMessages, tools: tools, model: model, temperature: temperature, stream: true)

            Task {
                var isStreamingReasoning = false
                do {
                    let (stream, response) = try await session.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)

                    switch result {
                    case .failure(let error):
                        // ... error handling ...
                        continuation.finish(throwing: error)
                        return
                    case .success:
                        break
                    }

                    try await SSEStreamParser.parse(stream: stream) { dataString in
                        guard let jsonData = dataString.data(using: .utf8) else { return }

                        let (finished, error, messageData, role, toolCalls) = self.parseDeltaJSONResponse(data: jsonData)

                        if let error = error {
                            throw error
                        }

                        var pendingToolCalls = toolCalls

                        if let messageData = messageData, !messageData.isEmpty {
                            if role == "reasoning" {
                                if !isStreamingReasoning {
                                    isStreamingReasoning = true
                                    continuation.yield(("<think>\n", nil))
                                }
                                continuation.yield((messageData, nil))
                            } else {
                                if isStreamingReasoning {
                                    isStreamingReasoning = false
                                    continuation.yield(("\n</think>\n\n", nil))
                                }
                                continuation.yield((messageData, pendingToolCalls))
                                pendingToolCalls = nil
                            }
                        } else if let toolCallsOnly = pendingToolCalls {
                            continuation.yield((nil, toolCallsOnly))
                            pendingToolCalls = nil
                        }

                        if finished {
                            if isStreamingReasoning {
                                isStreamingReasoning = false
                                continuation.yield(("\n</think>\n\n", nil))
                            }
                            continuation.finish()
                            return
                        }
                    }

                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        continuation.yield(("\n</think>\n\n", nil))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func prepareRequest(requestMessages: [[String: String]], tools: [[String: Any]]?, model: String, temperature: Float, stream: Bool) -> URLRequest {
        // Default implementation ignores tools. Handlers supporting tools must override.
        // We need to call the old prepareRequest signature if we want to maintain backward compatibility for other handlers?
        // Or just implement the base logic here.
        // Since `prepareRequest` was a protocol requirement, we can't easily call "super" from default impl.
        // But we can assume handlers override this.
        // Wait, `prepareRequest` in protocol didn't have body.
        // I'll provide a default that calls a legacy version?
        // Or just fail?
        // Most handlers override `prepareRequest`.
        // I'll update the signature in the protocol, so handlers MUST update or they won't conform.
        // This is a breaking change. I should update `BaseAPIHandler` too.
        fatalError("prepareRequest must be implemented by the handler")
    }
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        return nil
    }
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        return (false, nil, nil, nil, nil)
    }
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
        return prepareRequest(requestMessages: requestMessages, tools: nil, model: model, temperature: temperature, stream: true)
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

                    try await SSEStreamParser.parse(stream: stream) { dataString in
                        
                        if let jsonData = dataString.data(using: .utf8) {
                            let (finished, error, messageData, _) = self.parseDeltaJSONResponse(data: jsonData)

                            if let error = error {
                                throw error
                            } else if let messageData = messageData {
                                continuation.yield(messageData)
                            }

                            if finished {
                                continuation.finish()
                                return
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
    func sendMessage(_ requestMessages: [[String: String]], tools: [[String: Any]]? = nil, temperature: Float) async throws -> (String?, [ToolCall]?) {
        let request = prepareRequest(
            requestMessages: requestMessages,
            tools: tools,
            model: model,
            temperature: temperature,
            stream: false
        )

        let (data, response) = try await session.data(for: request)
        let result = self.handleAPIResponse(response, data: data, error: nil)

        switch result {
        case .success(let responseData):
            if let responseData = responseData {
                guard let (messageContent, _, toolCalls) = self.parseJSONResponse(data: responseData) else {
                    if let responseString = String(data: responseData, encoding: .utf8) {
                        print("APIProtocol Default Parsing Failed. Handler: \(self.name). Raw Response: \(responseString)")
                    }
                    throw APIError.decodingFailed("Failed to parse response")
                }
                return (messageContent, toolCalls)
            } else {
                throw APIError.invalidResponse
            }

        case .failure(let error):
            throw error
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
            tools: nil,
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
                            if let responseString = String(data: responseData, encoding: .utf8) {
                                print("APIProtocol Default Parsing Failed. Handler: \(self.name). Raw Response: \(responseString)")
                            }
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
