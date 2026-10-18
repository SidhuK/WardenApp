import Foundation
import os

// MARK: - Tavily Search Service

class TavilySearchService {
    private let baseURL = "https://api.tavily.com"
    private let session: URLSession
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Main Search Function
    
    /// Performs a complete search operation including status updates
    /// - Parameters:
    ///   - query: The search query
    ///   - onStatusUpdate: Callback for status updates (called on MainActor)
    /// - Returns: Tuple containing formatted context string, list of URLs, and source objects
    func performSearch(
        query: String,
        onStatusUpdate: @MainActor @escaping (SearchStatus) -> Void
    ) async throws -> (context: String, urls: [String], sources: [SearchSource]) {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] performSearch called")
        #endif

        // Update status: starting search
        await onStatusUpdate(.searching(query: query))
        
        let searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) 
            ?? AppConstants.tavilyDefaultSearchDepth
        let maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
        let resultsLimit = maxResults > 0 ? maxResults : AppConstants.tavilyDefaultMaxResults
        let includeAnswer = UserDefaults.standard.object(forKey: AppConstants.tavilyIncludeAnswerKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
        
        #if DEBUG
        WardenLog.app.debug(
            "[WebSearch] Settings depth=\(searchDepth, privacy: .public), maxResults=\(resultsLimit, privacy: .public), includeAnswer=\(includeAnswer, privacy: .public)"
        )
        #endif
        
        // Update status: fetching results
        await onStatusUpdate(.fetchingResults(sources: resultsLimit))
        
        let response = try await search(
            query: query,
            searchDepth: searchDepth,
            maxResults: resultsLimit,
            includeAnswer: includeAnswer
        )
        
        #if DEBUG
        WardenLog.app.debug("[WebSearch] Received \(response.results.count, privacy: .public) result(s)")
        #endif
        
        // Update status: processing results
        await onStatusUpdate(.processingResults)
        
        // Convert to SearchSource models
        let sources = response.results.map { result in
            SearchSource(
                title: result.title,
                url: result.url,
                score: result.score,
                publishedDate: result.publishedDate
            )
        }
        
        // Update status: completed
        await onStatusUpdate(.completed(sources: sources))
        
        // Extract URLs for citation linking
        let urls = response.results.map { $0.url }
        let context = formatResultsForContext(response)
        
        return (context, urls, sources)
    }

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
            WardenLog.app.debug("[WebSearch] Tavily response received: \(data.count, privacy: .public) byte(s)")
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
    
    // MARK: - Search Command Detection
    
    func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
        for prefix in AppConstants.searchCommandAliases {
            if message.lowercased().hasPrefix(prefix) {
                let query = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (true, query.isEmpty ? nil : query)
            }
        }
        return (false, nil)
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
    
    // MARK: - Citation Formatting
    
    func convertCitationsToLinks(_ text: String, urls: [String]) -> String {
        InlineCitations.convertToLinks(text, urls: urls)
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
