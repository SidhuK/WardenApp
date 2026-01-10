import Foundation

class BaseAPIHandler: APIService, @unchecked Sendable {
    let name: String
    let baseURL: URL
    internal let apiKey: String
    let model: String
    internal let session: URLSession
    internal let streamingSession: URLSession
    
    init(config: APIServiceConfiguration, session: URLSession, streamingSession: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
        self.streamingSession = streamingSession
    }
    
    convenience init(config: APIServiceConfiguration, session: URLSession) {
        self.init(config: config, session: session, streamingSession: session)
    }
    
    // MARK: - APIService Protocol Implementation
    
    // MARK: - APIService Protocol Implementation
    
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await sendMessage(requestMessages, tools: tools, temperature: temperature)
                completion(.success(result))
            } catch let error as APIError {
                completion(.failure(error))
            } catch {
                completion(.failure(.requestFailed(error)))
            }
        }
    }
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        // Canonical streaming implementation for all handlers.
        // Handlers should override only `prepareRequest` and `parseDeltaJSONResponse` as needed.
        return AsyncThrowingStream { continuation in
            let request: URLRequest
            do {
                request = try self.prepareRequest(
                    requestMessages: requestMessages,
                    tools: tools,
                    model: model,
                    temperature: temperature,
                    stream: true
                )
            } catch {
                continuation.finish(throwing: error)
                return
            }
            
            Task.detached(priority: .userInitiated) { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                var isStreamingReasoning = false
                do {
                    let (stream, response) = try await streamingSession.bytes(for: request)
                    let result = self.handleAPIResponse(response, data: nil, error: nil)
                    
                    switch result {
                    case .failure(let error):
                        let data = try await self.collectResponseBody(from: stream)
                        let remapped = self.handleAPIResponse(response, data: data, error: nil)
                        if case .failure(let detailedError) = remapped {
                            continuation.finish(throwing: detailedError)
                        }
                        else {
                            continuation.finish(throwing: error)
                        }
                        return
                    case .success:
                        break
                    }
                    
                    try await SSEStreamParser.parse(stream: stream) { [weak self] dataString in
                        guard let self = self else { return }
                        
                        // Check if task was cancelled before yielding
                        try Task.checkCancellation()
                        
                        if let data = dataString.data(using: .utf8) {
                            let (finished, error, messageData, role, toolCalls) = self.parseDeltaJSONResponse(data: data)
                            
                            if let error = error {
                                throw error
                            }
                            
                            var pendingToolCalls = toolCalls

                            if let messageData, !messageData.isEmpty {
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
                    }

                    if isStreamingReasoning {
                        isStreamingReasoning = false
                        continuation.yield(("\n</think>\n\n", nil))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    // Silently finish on cancellation - don't throw
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Methods to be overridden by subclasses
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) throws -> URLRequest {
        throw APIError.noApiService("Request building not implemented for \(name)")
    }
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        return nil
    }
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        return (false, nil, nil, nil, nil)
    }
    
    func fetchModels() async throws -> [AIModel] {
        []
    }
}

private extension BaseAPIHandler {
    func collectResponseBody(from stream: URLSession.AsyncBytes, maxBytes: Int = 1_048_576) async throws -> Data {
        var data = Data()
        data.reserveCapacity(min(16_384, maxBytes))
        for try await byte in stream {
            if data.count >= maxBytes {
                break
            }
            data.append(byte)
        }
        #if DEBUG
        WardenLog.streaming.debug("Captured streaming error body: \(data.count, privacy: .public) byte(s)")
        #endif
        return data
    }
}
