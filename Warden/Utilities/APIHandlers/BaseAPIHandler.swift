import Foundation

class BaseAPIHandler: APIService {
    let name: String
    let baseURL: URL
    internal let apiKey: String
    let model: String
    internal let session: URLSession
    
    init(config: APIServiceConfiguration, session: URLSession) {
        self.name = config.name
        self.baseURL = config.apiUrl
        self.apiKey = config.apiKey
        self.model = config.model
        self.session = session
    }
    
    // MARK: - APIService Protocol Implementation
    
    // MARK: - APIService Protocol Implementation
    
    func sendMessage(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float,
        completion: @escaping (Result<(String?, [ToolCall]?), APIError>) -> Void
    ) {
        defaultSendMessage(requestMessages, tools: tools, temperature: temperature, completion: completion)
    }
    
    func sendMessageStream(
        _ requestMessages: [[String: String]],
        tools: [[String: Any]]? = nil,
        temperature: Float
    ) async throws -> AsyncThrowingStream<(String?, [ToolCall]?), Error> {
        return AsyncThrowingStream { continuation in
            let request = self.prepareRequest(
                requestMessages: requestMessages,
                tools: tools,
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
                        let errorResponse = String(data: data, encoding: .utf8) ?? error.localizedDescription
                        continuation.finish(throwing: APIError.serverError(errorResponse))
                        return
                    case .success:
                        break
                    }
                    
                    try await SSEStreamParser.parse(stream: stream) { [weak self] dataString in
                        guard let self = self else { return }
                        
                        if let data = dataString.data(using: .utf8) {
                            let (finished, error, messageData, _, toolCalls) = self.parseDeltaJSONResponse(data: data)
                            
                            if let error = error {
                                throw error
                            }
                            
                            if messageData != nil || toolCalls != nil {
                                continuation.yield((messageData, toolCalls))
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
    
    // MARK: - Methods to be overridden by subclasses
    
    func prepareRequest(
        requestMessages: [[String: String]],
        tools: [[String: Any]]?,
        model: String,
        temperature: Float,
        stream: Bool
    ) -> URLRequest {
        fatalError("prepareRequest must be implemented by subclass")
    }
    
    func parseJSONResponse(data: Data) -> (String?, String?, [ToolCall]?)? {
        return nil
    }
    
    func parseDeltaJSONResponse(data: Data?) -> (Bool, Error?, String?, String?, [ToolCall]?) {
        return (false, nil, nil, nil, nil)
    }
    
    func fetchModels() async throws -> [AIModel] {
        fatalError("fetchModels must be implemented by subclass")
    }
}
