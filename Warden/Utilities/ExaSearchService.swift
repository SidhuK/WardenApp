import Foundation
import os

// MARK: - Exa Search Service

class ExaSearchService {
    private let baseURL = AppConstants.exaBaseURL
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func search(
        query: String,
        searchType: String = AppConstants.exaDefaultSearchType,
        maxResults: Int = AppConstants.webSearchDefaultMaxResults
    ) async throws -> ExaSearchResponse {
        guard let apiKey = getApiKey() else {
            throw WebSearchError.noApiKey
        }

        let searchRequest = ExaSearchRequest(
            query: query,
            type: searchType,
            numResults: maxResults,
            contents: ExaSearchContents(highlights: true, text: true)
        )

        let request = try prepareRequest(searchRequest, apiKey: apiKey)

        do {
            let (data, response) = try await session.data(for: request)

            #if DEBUG
            WardenLog.app.debug("[WebSearch] Exa response received: \(data.count, privacy: .public) byte(s)")
            #endif

            let result = handleResponse(response, data: data, error: nil)
            switch result {
            case .success(let responseData):
                let decoder = JSONDecoder()
                do {
                    return try decoder.decode(ExaSearchResponse.self, from: responseData)
                } catch {
                    throw WebSearchError.decodingFailed(error.localizedDescription)
                }
            case .failure(let error):
                throw error
            }
        } catch let error as WebSearchError {
            throw error
        } catch {
            throw WebSearchError.networkError(error)
        }
    }

    func formatResultsForContext(_ response: ExaSearchResponse, query: String) -> String {
        var formatted = "# Web Search Results for: \(query)\n\n"
        formatted += "## Detailed Sources:\n\n"

        for (index, result) in response.results.enumerated() {
            formatted += "### [\(index + 1)] \(result.title)\n"
            formatted += "**URL:** \(result.url)\n"
            if let date = result.publishedDate {
                formatted += "**Published:** \(date)\n"
            }
            if let author = result.author, !author.isEmpty {
                formatted += "**Author:** \(author)\n"
            }
            formatted += "**Content:** \(result.content)\n\n"
        }

        return formatted
    }

    private func getApiKey() -> String? {
        return TavilyKeyManager.shared.getApiKey(for: .exa)
    }

    private func prepareRequest(_ searchRequest: ExaSearchRequest, apiKey: String) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/search") else {
            throw WebSearchError.invalidRequest
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")

        let encoder = JSONEncoder()
        do {
            request.httpBody = try encoder.encode(searchRequest)
        } catch {
            throw WebSearchError.invalidRequest
        }

        return request
    }

    private func handleResponse(_ response: URLResponse?, data: Data?, error: Error?) -> Result<Data, WebSearchError> {
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
