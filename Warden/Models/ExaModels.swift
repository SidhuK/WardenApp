import Foundation

// MARK: - Exa Search Request

struct ExaSearchRequest: Encodable {
    let query: String
    let type: String
    let numResults: Int
    let contents: ExaSearchContents
}

struct ExaSearchContents: Encodable {
    let highlights: Bool
    let text: Bool
}

// MARK: - Exa Search Response

struct ExaSearchResponse: Decodable {
    let requestId: String?
    let searchType: String?
    let results: [ExaSearchResult]
}

// MARK: - Exa Search Result

struct ExaSearchResult: Decodable, Identifiable {
    let title: String
    let url: String
    let publishedDate: String?
    let author: String?
    let highlights: [String]?
    let summary: String?
    let text: String?

    var id: String { url }

    var content: String {
        if let highlights, !highlights.isEmpty {
            return highlights.joined(separator: "\n")
        }

        if let summary, !summary.isEmpty {
            return summary
        }

        return text ?? ""
    }
}
