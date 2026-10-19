import Foundation
import os

enum APIError: Error {
    case requestFailed(Error)
    case invalidResponse
    case decodingFailed(String)
    case unauthorized
    case rateLimited
    case serverError(String)
    case unknown(String)
    case noApiService(String)
    /// The provider is temporarily over capacity (HTTP 529 or an `overloaded_error` body).
    case overloaded
    /// Wraps another case with provider diagnostics. Use `base`/`context`/`adding(_:)` instead of matching directly.
    indirect case withContext(APIError, ProviderErrorContext)
}

/// Result of consuming a whole response stream.
struct StreamOutcome {
    var toolCalls: [ToolCall]?
    var usage: TokenUsage?
    /// When the first non-empty text (content or reasoning) arrived from the provider.
    var firstTokenAt: Date?
}

/// One element of a provider response stream. Usage is delivered once, in the final chunk.
struct StreamChunk {
    var text: String?
    var toolCalls: [ToolCall]?
    var usage: TokenUsage?

    init(text: String? = nil, toolCalls: [ToolCall]? = nil, usage: TokenUsage? = nil) {
        self.text = text
        self.toolCalls = toolCalls
        self.usage = usage
    }
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

/// Controls whether a handler should attempt provider-native file/document attachments,
/// or force all non-image attachments to be inlined as extracted text.
enum AttachmentPolicy: String, Sendable {
    case preferProviderAttachments
    case inlineTextOnly
}

protocol APIService {
    var name: String { get }
    var baseURL: URL { get }
    var session: URLSession { get }
    var model: String { get }

    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        settings: GenerationSettings,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    )

    /// Non-streaming request whose result also carries token usage when the provider reports it.
    func sendMessageWithUsage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        settings: GenerationSettings,
        completion: @escaping (Result<StreamChunk, APIError>) -> Void
    )
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<StreamChunk, Error>
    
    func fetchModels() async throws -> [AIModel]
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        attachmentPolicy: AttachmentPolicy,
        stream: Bool
    ) async throws -> URLRequest
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)?
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?)
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
            let apiError = ProviderErrorMapper.error(for: httpResponse, data: data)
            return .failure(apiError.adding(ProviderErrorContext(providerType: name, model: model)))
        }

        return .success(data)
    }

    /// Default implementation of SSE comment checking
    func isNotSSEComment(_ string: String) -> Bool {
        return !string.starts(with: ":")
    }

    /// Default implementation of non-streaming message sending
    /// Consolidates shared request/response handling across all handlers
    /// Handlers only need to override parseJSONResponse for their specific format
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> (String?, [ToolCall]?) {
        let result = try await sendMessageReturningUsage(requestMessages, tools: tools, settings: settings)
        return (result.text, result.toolCalls)
    }

    /// Non-streaming request that also reports token usage parsed from the response body.
    func sendMessageReturningUsage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> StreamChunk {
        func execute(settings: GenerationSettings, attachmentPolicy: AttachmentPolicy) async throws -> StreamChunk {
            let request = try await prepareRequest(
                requestMessages: requestMessages,
                tools: tools,
                model: model,
                settings: settings,
                attachmentPolicy: attachmentPolicy,
                stream: false
            )

            let (data, response) = try await session.data(for: request)
            let result = self.handleAPIResponse(response, data: data, error: nil)

            switch result {
            case .success(let responseData):
                if let responseData = responseData {
                    guard let (messageContent, _, toolCalls) = self.parseJSONResponse(data: responseData) else {
                        #if DEBUG
                        WardenLog.app.debug(
                            "Default parsing failed. Handler: \(self.name, privacy: .public). Response bytes: \(responseData.count, privacy: .public)"
                        )
                        #endif
                        throw APIError.decodingFailed("Failed to parse response")
                    }
                    return StreamChunk(
                        text: messageContent,
                        toolCalls: toolCalls,
                        usage: UsageExtractor.usage(from: responseData)
                    )
                } else {
                    throw APIError.invalidResponse
                }

            case .failure(let error):
                throw error
            }
        }

        var attemptSettings = settings
        var didRetryWithoutReasoning = false
        var attachmentPolicy: AttachmentPolicy = .preferProviderAttachments
        var didRetryWithoutAttachments = false

        while true {
            do {
                return try await execute(settings: attemptSettings, attachmentPolicy: attachmentPolicy)
            } catch let error as APIError {
                if !didRetryWithoutAttachments,
                   AttachmentCompatibility.shouldRetryWithoutFileAttachments(attachmentPolicy: attachmentPolicy, error: error) {
                    didRetryWithoutAttachments = true
                    attachmentPolicy = .inlineTextOnly
                    WardenLog.app.notice(
                        "Retrying request without file attachments due to unsupported parameter (provider: \(self.name, privacy: .public))"
                    )
                    continue
                }

                if !didRetryWithoutReasoning,
                   ReasoningCompatibility.shouldRetryWithoutReasoning(settings: attemptSettings, error: error) {
                    didRetryWithoutReasoning = true
                    attemptSettings.reasoningEffort = .off
                    WardenLog.app.notice(
                        "Retrying request without reasoning fields due to unsupported parameter (provider: \(self.name, privacy: .public))"
                    )
                    continue
                }

                throw error.adding(ProviderErrorContext(providerType: name, model: model))
            }
        }
    }

}

enum ReasoningCompatibility {
    static func shouldRetryWithoutReasoning(settings: GenerationSettings, error: APIError) -> Bool {
        guard settings.reasoningEffort != .off else { return false }

        switch error.base {
        case .serverError, .unknown:
            break
        default:
            return false
        }
        guard let errorText = error.compatibilityText else { return false }

        let lower = errorText.lowercased()
        let hasReasoningParam = lower.contains("reasoning_effort")
            || lower.contains("include_reasoning")
            || lower.contains("\"reasoning\"")
            || lower.contains("thinking")
        
        guard hasReasoningParam else { return false }

        return lower.contains("unknown")
            || lower.contains("unrecognized")
            || lower.contains("unsupported")
            || lower.contains("invalid")
            || lower.contains("not allowed")
            || lower.contains("additional properties")
            || lower.contains("not supported")
    }
}

enum AttachmentCompatibility {
    static func shouldRetryWithoutFileAttachments(attachmentPolicy: AttachmentPolicy, error: APIError) -> Bool {
        guard attachmentPolicy != .inlineTextOnly else { return false }

        switch error.base {
        case .serverError, .unknown:
            break
        default:
            return false
        }
        guard let errorText = error.compatibilityText else { return false }

        let lower = errorText.lowercased()
        let mentionsAttachmentFields = lower.contains("document")
            || lower.contains("file")
            || lower.contains("attachment")
            || lower.contains("media_type")
            || lower.contains("input_file")
            || lower.contains("file_data")
            || lower.contains("filename")

        guard mentionsAttachmentFields else { return false }

        return lower.contains("unknown")
            || lower.contains("unrecognized")
            || lower.contains("unsupported")
            || lower.contains("invalid")
            || lower.contains("not allowed")
            || lower.contains("additional properties")
            || lower.contains("not supported")
    }
}

enum StreamUsageCompatibility {
    /// True when an OpenAI-compatible server rejected the `stream_options` field.
    static func shouldRetryWithoutStreamUsage(settings: GenerationSettings, error: APIError) -> Bool {
        guard settings.includeStreamUsage != false else { return false }
        switch error.base {
        case .serverError, .unknown:
            break
        default:
            return false
        }
        guard let lower = error.compatibilityText?.lowercased() else { return false }
        return lower.contains("stream_options") || lower.contains("include_usage")
    }
}
