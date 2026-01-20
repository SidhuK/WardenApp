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
        settings: GenerationSettings,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        let completionController = CompletionController(completion)

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await sendMessage(requestMessages, tools: tools, settings: settings)
                await completionController.call(.success(result))
            } catch let error as APIError {
                await completionController.call(.failure(error))
            } catch {
                await completionController.call(.failure(.requestFailed(error)))
            }
        }
    }
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        // Canonical streaming implementation for all handlers.
        // Handlers should override only `prepareRequest` and `parseDeltaJSONResponse` as needed.
        return AsyncThrowingStream { continuation in
            let controller = StreamContinuationController(continuation)

            let streamingTask = Task(priority: .userInitiated) { [weak self] in
                guard let self else {
                    await controller.finish()
                    return
                }
                do {
                    var attemptSettings = settings
                    var didRetryWithoutReasoning = false

                    while true {
                        let request = try self.prepareRequest(
                            requestMessages: requestMessages,
                            tools: tools,
                            model: model,
                            settings: attemptSettings,
                            stream: true
                        )

                        let (stream, response) = try await streamingSession.bytes(for: request)
                        let result = self.handleAPIResponse(response, data: nil, error: nil)

                        switch result {
                        case .failure(let error):
                            let data = try await self.collectResponseBody(from: stream)
                            let remapped = self.handleAPIResponse(response, data: data, error: nil)

                            let detailedError: APIError
                            if case .failure(let failure) = remapped {
                                detailedError = failure
                            } else {
                                detailedError = error
                            }

                            if !didRetryWithoutReasoning,
                               ReasoningCompatibility.shouldRetryWithoutReasoning(settings: attemptSettings, error: detailedError) {
                                didRetryWithoutReasoning = true
                                attemptSettings = GenerationSettings(temperature: attemptSettings.temperature, reasoningEffort: .off)
                                WardenLog.app.notice(
                                    "Retrying stream without reasoning fields due to unsupported parameter (provider: \(self.name, privacy: .public))"
                                )
                                continue
                            }

                            await controller.finish(throwing: detailedError)
                            return
                        case .success:
                            break
                        }

                        var isStreamingReasoning = false

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
                                            await controller.yield(("<think>\n", nil))
                                        }
                                        await controller.yield((messageData, nil))
                                    } else {
                                        if isStreamingReasoning {
                                            isStreamingReasoning = false
                                            await controller.yield(("\n</think>\n\n", nil))
                                        }
                                        await controller.yield((messageData, pendingToolCalls))
                                        pendingToolCalls = nil
                                    }
                                } else if let toolCallsOnly = pendingToolCalls {
                                    await controller.yield((nil, toolCallsOnly))
                                    pendingToolCalls = nil
                                }

                                if finished {
                                    if isStreamingReasoning {
                                        isStreamingReasoning = false
                                        await controller.yield(("\n</think>\n\n", nil))
                                    }
                                    await controller.finish()
                                    return
                                }
                            }
                        }

                        if isStreamingReasoning {
                            isStreamingReasoning = false
                            await controller.yield(("\n</think>\n\n", nil))
                        }

                        await controller.finish()
                        return
                    }
                } catch is CancellationError {
                    // Silently finish on cancellation - don't throw
                    await controller.finish()
                } catch {
                    await controller.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamingTask.cancel()
            }
        }
    }
    
    // MARK: - Methods to be overridden by subclasses
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
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
    actor StreamContinuationController {
        typealias Element = (String?, [ToolCall]?)

        private var continuation: AsyncThrowingStream<Element, Error>.Continuation?

        init(_ continuation: AsyncThrowingStream<Element, Error>.Continuation) {
            self.continuation = continuation
        }

        func yield(_ value: Element) {
            continuation?.yield(value)
        }

        func finish() {
            continuation?.finish()
            continuation = nil
        }

        func finish(throwing error: Error) {
            continuation?.finish(throwing: error)
            continuation = nil
        }
    }

    actor CompletionController {
        private let completion: (Result<(String?, [ToolCall]?), APIError>) -> Void

        init(_ completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void) {
            self.completion = completion
        }

        func call(_ result: Result<(String?, [ToolCall]?), APIError>) async {
            await MainActor.run {
                completion(result)
            }
        }
    }

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
