import Foundation

// MARK: - Tavily Error

enum TavilyError: Error {
    case noApiKey
    case invalidRequest
    case networkError(Error)
    case invalidResponse
    case decodingFailed(String)
    case serverError(String)
    case unauthorized
    case rateLimited
}

extension TavilyError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Tavily API key not configured. Please add it in Preferences > Web Search."
        case .invalidRequest:
            return "Invalid search request. Please try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from Tavily API."
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .serverError(let message):
            return "Tavily server error: \(message)"
        case .unauthorized:
            return "Invalid Tavily API key. Please check your API key in Preferences."
        case .rateLimited:
            return "Tavily API rate limit exceeded. Please try again later."
        }
    }
}

// MARK: - Tavily Search Service

class TavilySearchService {
    private let baseURL = "https://api.tavily.com"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Main Search Function
    
    func search(
        query: String,
        searchDepth: String = "basic",
        maxResults: Int = 5,
        includeAnswer: Bool = true
    ) async throws -> TavilySearchResponse {
        guard let apiKey = getApiKey() else {
            throw TavilyError.noApiKey
        }
        
        let searchRequest = TavilySearchRequest(
            apiKey: apiKey,
            query: query,
            searchDepth: searchDepth,
            includeImages: false,
            includeAnswer: includeAnswer,
            includeRawContent: false,
            maxResults: maxResults
        )
        
        let request = try prepareRequest(searchRequest)
        
        do {
            let (data, response) = try await session.data(for: request)
            
            #if DEBUG
            if let responseString = String(data: data, encoding: .utf8) {
                print("🔍 Tavily Response: \(responseString)")
            }
            #endif
            
            let result = handleResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                let decoder = JSONDecoder()
                do {
                    return try decoder.decode(TavilySearchResponse.self, from: responseData)
                } catch {
                    throw TavilyError.decodingFailed(error.localizedDescription)
                }
            case .failure(let error):
                throw error
            }
        } catch let error as TavilyError {
            throw error
        } catch {
            throw TavilyError.networkError(error)
        }
    }
    
    // MARK: - Format Results for AI Context
    
    func formatResultsForContext(_ response: TavilySearchResponse) -> String {
        var formatted = "# Web Search Results for: \(response.query)\n\n"
        
        if let answer = response.answer, !answer.isEmpty {
            formatted += "## Quick Answer:\n\(answer)\n\n"
        }
        
        formatted += "## Detailed Sources:\n\n"
        
        for (index, result) in response.results.enumerated() {
            formatted += "### [\(index + 1)] \(result.title)\n"
            formatted += "**URL:** \(result.url)\n"
            if let date = result.publishedDate {
                formatted += "**Published:** \(date)\n"
            }
            formatted += "**Content:** \(result.content)\n\n"
        }
        
        return formatted
    }
    
    // MARK: - Private Helper Methods
    
    private func getApiKey() -> String? {
        return TavilyKeyManager.shared.getApiKey()
    }
    
    private func prepareRequest(_ searchRequest: TavilySearchRequest) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/search") else {
            throw TavilyError.invalidRequest
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(searchRequest)
        } catch {
            throw TavilyError.invalidRequest
        }
        
        #if DEBUG
        print("🔍 Tavily Search Request: \(searchRequest.query)")
        #endif
        
        return request
    }
    
    private func handleResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data, TavilyError> {
        if let error = error {
            return .failure(.networkError(error))
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        
        guard let data = data else {
            return .failure(.invalidResponse)
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return .success(data)
        case 401:
            return .failure(.unauthorized)
        case 429:
            return .failure(.rateLimited)
        case 400...499:
            if let errorResponse = String(data: data, encoding: .utf8) {
                return .failure(.serverError("Client Error: \(errorResponse)"))
            }
            return .failure(.serverError("Client Error: HTTP \(httpResponse.statusCode)"))
        case 500...599:
            if let errorResponse = String(data: data, encoding: .utf8) {
                return .failure(.serverError("Server Error: \(errorResponse)"))
            }
            return .failure(.serverError("Server Error: HTTP \(httpResponse.statusCode)"))
        default:
            return .failure(.serverError("Unknown error: HTTP \(httpResponse.statusCode)"))
        }
    }
}
