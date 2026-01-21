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
        settings: GenerationSettings,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    )
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        settings: GenerationSettings
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error>
    
    func fetchModels() async throws -> [AIModel]
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        settings: GenerationSettings,
        stream: Bool
    ) throws -> URLRequest
    
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

    /// Default implementation of non-streaming message sending
    /// Consolidates shared request/response handling across all handlers
    /// Handlers only need to override parseJSONResponse for their specific format
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        settings: GenerationSettings
    ) async throws -> (String?, [ToolCall]?) {
        func execute(settings: GenerationSettings) async throws -> (String?, [ToolCall]?) {
            let request = try prepareRequest(
                requestMessages: requestMessages,
                tools: tools,
                model: model,
                settings: settings,
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
                    return (messageContent, toolCalls)
                } else {
                    throw APIError.invalidResponse
                }

            case .failure(let error):
                throw error
            }
        }

        do {
            return try await execute(settings: settings)
        } catch let error as APIError {
            guard settings.reasoningEffort != .off,
                  ReasoningCompatibility.shouldRetryWithoutReasoning(settings: settings, error: error)
            else {
                throw error
            }

            WardenLog.app.notice(
                "Retrying request without reasoning fields due to unsupported parameter (provider: \(self.name, privacy: .public))"
            )

            let retrySettings = GenerationSettings(temperature: settings.temperature, reasoningEffort: .off)
            return try await execute(settings: retrySettings)
        }
    }

}

enum ReasoningCompatibility {
    static func shouldRetryWithoutReasoning(settings: GenerationSettings, error: APIError) -> Bool {
        guard settings.reasoningEffort != .off else { return false }

        let errorText: String
        switch error {
        case .serverError(let message):
            errorText = message
        case .unknown(let message):
            errorText = message
        default:
            return false
        }

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
