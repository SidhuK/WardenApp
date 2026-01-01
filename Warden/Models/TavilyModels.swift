import Foundation

// MARK: - Tavily Search Request

struct TavilySearchRequest: Codable {
    let apiKey: String
    let query: String
    let searchDepth: String
    let includeImages: Bool
    let includeAnswer: Bool
    let includeRawContent: Bool
    let maxResults: Int
    
    enum CodingKeys: String, CodingKey {
        case apiKey = "api_key"
        case query
        case searchDepth = "search_depth"
        case includeImages = "include_images"
        case includeAnswer = "include_answer"
        case includeRawContent = "include_raw_content"
        case maxResults = "max_results"
    }
}

// MARK: - Tavily Search Response

struct TavilySearchResponse: Codable {
    let answer: String?
    let query: String
    let responseTime: Double
    let images: [String]
    let results: [TavilySearchResult]
    
    enum CodingKeys: String, CodingKey {
        case answer
        case query
        case responseTime = "response_time"
        case images
        case results
    }
}

// MARK: - Tavily Search Result

struct TavilySearchResult: Codable, Identifiable {
    let title: String
    let url: String
    let content: String
    let score: Double
    let publishedDate: String?

    var id: String { url }
    
    enum CodingKeys: String, CodingKey {
        case title
        case url
        case content
        case score
        case publishedDate = "published_date"
    }
}
