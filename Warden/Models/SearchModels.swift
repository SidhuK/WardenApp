import Foundation

// MARK: - Tool Call Status

enum ToolCallStatus: Equatable {
    case calling(toolName: String)
    case executing(toolName: String, progress: String?)
    case completed(toolName: String, success: Bool)
    case failed(toolName: String, error: String)
    
    static func == (lhs: ToolCallStatus, rhs: ToolCallStatus) -> Bool {
        switch (lhs, rhs) {
        case (.calling(let n1), .calling(let n2)):
            return n1 == n2
        case (.executing(let n1, _), .executing(let n2, _)):
            return n1 == n2
        case (.completed(let n1, let s1), .completed(let n2, let s2)):
            return n1 == n2 && s1 == s2
        case (.failed(let n1, _), .failed(let n2, _)):
            return n1 == n2
        default:
            return false
        }
    }
    
    var toolName: String {
        switch self {
        case .calling(let name), .executing(let name, _), .completed(let name, _), .failed(let name, _):
            return name
        }
    }
}

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
