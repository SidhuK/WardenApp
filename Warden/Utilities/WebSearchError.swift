import Foundation

// MARK: - Web Search Error

enum WebSearchError: Error {
    case noApiKey
    case invalidRequest
    case networkError(Error)
    case invalidResponse
    case decodingFailed(String)
    case serverError(String)
    case unauthorized
    case rateLimited
}

extension WebSearchError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noApiKey:
            return "Web search API key not configured. Please add it in Preferences > Web Search."
        case .invalidRequest:
            return "Invalid search request. Please try again."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from web search API."
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .serverError(let message):
            return "Web search server error: \(message)"
        case .unauthorized:
            return "Invalid web search API key. Please check your API key in Preferences."
        case .rateLimited:
            return "Web search API rate limit exceeded. Please try again later."
        }
    }
}

typealias TavilyError = WebSearchError
