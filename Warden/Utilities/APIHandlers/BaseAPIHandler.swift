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
        sendMessageWithUsage(requestMessages, tools: tools, settings: settings) { result in
            completion(result.map { ($0.text, $0.toolCalls) })
        }
    }

    func sendMessageWithUsage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings,
        completion: @escaping (Result<StreamChunk, APIError>) -> Void
    ) {
        let completionController = CompletionController(completion)

        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let result = try await sendMessageReturningUsage(requestMessages, tools: tools, settings: settings)
                await completionController.call(.success(result))
            } catch let error as APIError {
                await completionController.call(.failure(error))
            } catch {
                await completionController.call(
                    .failure(APIError.requestFailed(error).adding(self.errorContext))
                )
            }
        }
    }

    /// Provider details attached to errors raised by this handler.
    var errorContext: ProviderErrorContext {
        ProviderErrorContext(providerType: name, model: model)
    }

    /// Seconds to keep reading after a provider signals completion, waiting for a trailing usage
    /// event or `[DONE]`. Bounds the wait for servers that never close the connection.
    static let postFinishGracePeriod: TimeInterval = 2.5

    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<StreamChunk, Error> {
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
                    var attachmentPolicy: AttachmentPolicy = .preferProviderAttachments
                    var didRetryWithoutAttachments = false
                    var didRetryWithoutStreamUsage = false

                    while true {
                        let request = try await self.prepareRequest(
                            requestMessages: requestMessages,
                            tools: tools,
                            model: model,
                            settings: attemptSettings,
                            attachmentPolicy: attachmentPolicy,
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

                            if !didRetryWithoutAttachments,
                               AttachmentCompatibility.shouldRetryWithoutFileAttachments(
                                   attachmentPolicy: attachmentPolicy,
                                   error: detailedError
                               )
                            {
                                didRetryWithoutAttachments = true
                                attachmentPolicy = .inlineTextOnly
                                WardenLog.app.notice(
                                    "Retrying stream without file attachments due to unsupported parameter (provider: \(self.name, privacy: .public))"
                                )
                                continue
                            }

                            if !didRetryWithoutStreamUsage,
                               StreamUsageCompatibility.shouldRetryWithoutStreamUsage(
                                   settings: attemptSettings,
                                   error: detailedError
                               )
                            {
                                didRetryWithoutStreamUsage = true
                                attemptSettings.includeStreamUsage = false
                                WardenLog.app.notice(
                                    "Retrying stream without stream_options due to unsupported parameter (provider: \(self.name, privacy: .public))"
                                )
                                continue
                            }

                            if !didRetryWithoutReasoning,
                               ReasoningCompatibility.shouldRetryWithoutReasoning(settings: attemptSettings, error: detailedError) {
                                didRetryWithoutReasoning = true
                                attemptSettings.reasoningEffort = .off
                                WardenLog.app.notice(
                                    "Retrying stream without reasoning fields due to unsupported parameter (provider: \(self.name, privacy: .public))"
                                )
                                continue
                            }

                            await controller.finish(throwing: detailedError.adding(self.errorContext))
                            return
                        case .success:
                            break
                        }

                        let state = StreamParseState()
                        let parseTask = Task { [weak self] in
                            try await SSEStreamParser.parse(stream: stream) { [weak self] dataString in
                                guard let self = self else { return }

                                // Check if task was cancelled before yielding
                                try Task.checkCancellation()

                                if dataString == "[DONE]" {
                                    throw StreamEndSignal()
                                }

                                guard let data = dataString.data(using: .utf8) else { return }

                                if let usage = self.extractUsage(fromStreamEvent: data) {
                                    await state.record(usage: usage)
                                }

                                if await state.finished {
                                    // Content after completion is ignored; only trailing usage matters.
                                    return
                                }

                                let (finished, error, messageData, role, toolCalls) = self.parseDeltaJSONResponse(data: data)

                                if let error = error {
                                    throw error
                                }

                                var pendingToolCalls = toolCalls

                                if let messageData, !messageData.isEmpty {
                                    if role == "reasoning" {
                                        if await state.beginReasoning() {
                                            await controller.yield(StreamChunk(text: "<think>\n"))
                                        }
                                        await controller.yield(StreamChunk(text: messageData))
                                    } else {
                                        if await state.endReasoning() {
                                            await controller.yield(StreamChunk(text: "\n</think>\n\n"))
                                        }
                                        await controller.yield(StreamChunk(text: messageData, toolCalls: pendingToolCalls))
                                        pendingToolCalls = nil
                                    }
                                } else if let toolCallsOnly = pendingToolCalls {
                                    await controller.yield(StreamChunk(toolCalls: toolCallsOnly))
                                    pendingToolCalls = nil
                                }

                                if finished {
                                    if await state.endReasoning() {
                                        await controller.yield(StreamChunk(text: "\n</think>\n\n"))
                                    }
                                    await state.markFinished()
                                }
                            }
                        }

                        do {
                            try await withTaskCancellationHandler {
                                try await Self.awaitParse(parseTask, state: state)
                            } onCancel: {
                                parseTask.cancel()
                            }
                        } catch is StreamEndSignal {
                            // `[DONE]` received.
                        } catch {
                            // A provider that already signalled completion may drop or reset the
                            // connection while we wait for trailing usage; that is not a failure.
                            guard await state.finished, !Task.isCancelled else { throw error }
                        }

                        try Task.checkCancellation()

                        if await state.endReasoning() {
                            await controller.yield(StreamChunk(text: "\n</think>\n\n"))
                        }

                        if let usage = await state.usage {
                            await controller.yield(StreamChunk(usage: usage))
                        }

                        await controller.finish()
                        return
                    }
                } catch is CancellationError {
                    // Silently finish on cancellation - don't throw
                    await controller.finish()
                } catch let error as APIError {
                    await controller.finish(throwing: error.adding(self.errorContext))
                } catch {
                    if Task.isCancelled {
                        await controller.finish()
                    } else {
                        await controller.finish(throwing: error)
                    }
                }
            }

            continuation.onTermination = { @Sendable _ in
                streamingTask.cancel()
            }
        }
    }

    /// Parses token usage from one raw stream event. Handlers with unusual shapes can override.
    func extractUsage(fromStreamEvent data: Data) -> TokenUsage? {
        UsageExtractor.usage(from: data)
    }

    /// Waits for `parseTask` to end. After the provider signals completion, the parse task keeps
    /// draining the connection for trailing usage, but only for `postFinishGracePeriod` seconds so a
    /// server that never closes the stream cannot stall the response.
    private static func awaitParse(_ parseTask: Task<Void, Error>, state: StreamParseState) async throws {
        let grace = postFinishGracePeriod
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resolver = OnceResolver(continuation)

            Task {
                do {
                    try await parseTask.value
                    await resolver.resolve(.success(()))
                } catch {
                    await resolver.resolve(.failure(error))
                }
            }

            Task {
                while await !resolver.isResolved {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    if let finishedAt = await state.finishedAt, Date().timeIntervalSince(finishedAt) >= grace {
                        parseTask.cancel()
                        await resolver.resolve(.success(()))
                        return
                    }
                }
            }
        }
    }

    // MARK: - Methods to be overridden by subclasses
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        attachmentPolicy: AttachmentPolicy,
        stream: Bool
    ) async throws -> URLRequest {
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

private struct StreamEndSignal: Error {}

private extension BaseAPIHandler {
    actor StreamParseState {
        private(set) var usage: TokenUsage?
        private(set) var finishedAt: Date?
        private var isStreamingReasoning = false

        var finished: Bool { finishedAt != nil }

        func record(usage newUsage: TokenUsage) {
            usage = usage.map { $0.merged(with: newUsage) } ?? newUsage
        }

        func markFinished() {
            if finishedAt == nil {
                finishedAt = Date()
            }
        }

        /// Returns true when this call opened a reasoning block.
        func beginReasoning() -> Bool {
            guard !isStreamingReasoning else { return false }
            isStreamingReasoning = true
            return true
        }

        /// Returns true when this call closed an open reasoning block.
        func endReasoning() -> Bool {
            guard isStreamingReasoning else { return false }
            isStreamingReasoning = false
            return true
        }
    }

    actor OnceResolver {
        private var continuation: CheckedContinuation<Void, Error>?

        init(_ continuation: CheckedContinuation<Void, Error>) {
            self.continuation = continuation
        }

        var isResolved: Bool { continuation == nil }

        func resolve(_ result: Result<Void, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

    actor StreamContinuationController {
        typealias Element = StreamChunk

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
        private let completion: (Result<StreamChunk, APIError>) -> Void

        init(_ completion: @escaping (Result<StreamChunk, APIError>) -> Void) {
            self.completion = completion
        }

        func call(_ result: Result<StreamChunk, APIError>) async {
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
