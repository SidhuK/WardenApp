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
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#, options: [])
    
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
        print("🔍 [WebSearch] performSearch called with query: \(query)")
        
        // Update status: starting search
        await onStatusUpdate(.searching(query: query))
        
        let searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey) 
            ?? AppConstants.tavilyDefaultSearchDepth
        let maxResults = UserDefaults.standard.integer(forKey: AppConstants.tavilyMaxResultsKey)
        let resultsLimit = maxResults > 0 ? maxResults : AppConstants.tavilyDefaultMaxResults
        let includeAnswer = UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)
        
        print("🔍 [WebSearch] Search settings - depth: \(searchDepth), maxResults: \(resultsLimit), includeAnswer: \(includeAnswer)")
        
        // Check if API key exists
        if let apiKey = getApiKey() {
            print("🔍 [WebSearch] API key found: \(String(apiKey.prefix(10)))...")
        } else {
            print("❌ [WebSearch] No API key found!")
        }
        
        // Update status: fetching results
        await onStatusUpdate(.fetchingResults(sources: resultsLimit))
        
        let response = try await search(
            query: query,
            searchDepth: searchDepth,
            maxResults: resultsLimit,
            includeAnswer: includeAnswer
        )
        
        print("🔍 [WebSearch] Got \(response.results.count) results from Tavily")
        
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
        guard !urls.isEmpty else {
            return text
        }
        
        var result = text
        print("🔗 [Citations] Converting inline citations with \(urls.count) URLs")
        
        // Regex to match standalone [n] style citations:
        // - \[(\d+)\] captures the number
        // - (?=[^\[]|\z) is a light guard to avoid overlapping like [[1]]
        // We will additionally validate boundaries in code.
        if let regex = Self.citationRegex {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))
            
            // Replace from the end to preserve indices
            var mutableResult = result as NSString
            
            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range(at: 0)
                let numberRange = match.range(at: 1)
                
                let numberString = nsString.substring(with: numberRange)
                guard let number = Int(numberString) else { continue }
                
                // Map [1] -> urls[0], [2] -> urls[1], etc.
                let urlIndex = number - 1
                guard urlIndex >= 0 && urlIndex < urls.count else { continue }
                
                // Ensure this [n] is "standalone-ish":
                // - Preceded by start, whitespace, punctuation, or '('
                // - Followed by end, whitespace, punctuation, or ')'
                let start = fullRange.location
                let end = fullRange.location + fullRange.length

                // Use Swift String indices for safe boundary detection over extended grapheme clusters.
                let stringStartIndex = result.startIndex
                let stringEndIndex = result.endIndex

                let startIndex = result.index(stringStartIndex, offsetBy: start)
                let endIndex = result.index(stringStartIndex, offsetBy: end)

                let prevChar: Character? = (startIndex > stringStartIndex)
                    ? result[result.index(before: startIndex)]
                    : nil

                let nextChar: Character? = (endIndex < stringEndIndex)
                    ? result[endIndex]
                    : nil

                func isBoundary(_ ch: Character?) -> Bool {
                    guard let ch = ch else { return true } // Treat start/end as boundary
                    if ch.isWhitespace { return true }

                    // Delimiters where citations should be considered standalone-ish
                    let delimiters: Set<Character> = [".", ",", ";", ":", "!", "?", "(", ")", "[", "]"]
                    return delimiters.contains(ch)
                }
                
                guard isBoundary(prevChar), isBoundary(nextChar) else {
                    continue
                }
                
                let url = urls[urlIndex]
                let replacement = "[\(number)](\(url))"
                mutableResult = mutableResult.replacingCharacters(in: fullRange, with: replacement) as NSString
                print("🔗 [Citations] Replaced [\(number)] with markdown link -> \(url)")
            }
            
            result = mutableResult as String
        } else {
            print("❌ [Citations] Failed to create regex for inline citations")
        }
        
        return result
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
