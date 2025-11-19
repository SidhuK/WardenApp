import Foundation

// MARK: - Search Status

enum SearchStatus: Equatable {
    case searching(query: String)
    case fetchingResults(sources: Int)
    case processingResults
    case completed(sources: [SearchSource])
    case failed(Error)
    
    static func == (lhs: SearchStatus, rhs: SearchStatus) -> Bool {
        switch (lhs, rhs) {
        case (.searching(let q1), .searching(let q2)):
            return q1 == q2
        case (.fetchingResults(let s1), .fetchingResults(let s2)):
            return s1 == s2
        case (.processingResults, .processingResults):
            return true
        case (.completed(let sources1), .completed(let sources2)):
            return sources1 == sources2
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Search Source

struct SearchSource: Identifiable, Codable, Equatable {
    let id = UUID()
    let title: String
    let url: String
    let score: Double
    let publishedDate: String?
    
    enum CodingKeys: String, CodingKey {
        case title, url, score, publishedDate
    }
}

// MARK: - Message Search Metadata

struct MessageSearchMetadata: Codable {
    let query: String
    let sources: [SearchSource]
    let searchTime: Date
    let resultCount: Int
}
