import Foundation

// MARK: - Tool Call Status

public enum WardenToolCallStatus: Equatable, Identifiable, Codable {
    case calling(toolName: String)
    case executing(toolName: String, progress: String?)
    case completed(toolName: String, success: Bool, result: String? = nil)
    case failed(toolName: String, error: String)
    
    public var id: String { toolName }
    
    enum CodingKeys: String, CodingKey {
        case type, toolName, progress, success, result, error
    }
    
    public enum StatusType: String, Codable {
        case calling, executing, completed, failed
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(StatusType.self, forKey: .type)
        let toolName = try container.decode(String.self, forKey: .toolName)
        
        switch type {
        case .calling:
            self = .calling(toolName: toolName)
        case .executing:
            let progress = try container.decodeIfPresent(String.self, forKey: .progress)
            self = .executing(toolName: toolName, progress: progress)
        case .completed:
            let success = try container.decode(Bool.self, forKey: .success)
            let result = try container.decodeIfPresent(String.self, forKey: .result)
            self = .completed(toolName: toolName, success: success, result: result)
        case .failed:
            let error = try container.decode(String.self, forKey: .error)
            self = .failed(toolName: toolName, error: error)
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(toolName, forKey: .toolName)
        
        switch self {
        case .calling:
            try container.encode(StatusType.calling, forKey: .type)
        case .executing(_, let progress):
            try container.encode(StatusType.executing, forKey: .type)
            try container.encodeIfPresent(progress, forKey: .progress)
        case .completed(_, let success, let result):
            try container.encode(StatusType.completed, forKey: .type)
            try container.encode(success, forKey: .success)
            try container.encodeIfPresent(result, forKey: .result)
        case .failed(_, let error):
            try container.encode(StatusType.failed, forKey: .type)
            try container.encode(error, forKey: .error)
        }
    }
    
    public static func == (lhs: WardenToolCallStatus, rhs: WardenToolCallStatus) -> Bool {
        switch (lhs, rhs) {
        case (.calling(let n1), .calling(let n2)):
            return n1 == n2
        case (.executing(let n1, _), .executing(let n2, _)):
            return n1 == n2
        case (.completed(let n1, let s1, _), .completed(let n2, let s2, _)):
            return n1 == n2 && s1 == s2
        case (.failed(let n1, _), .failed(let n2, _)):
            return n1 == n2
        default:
            return false
        }
    }
    
    public var toolName: String {
        switch self {
        case .calling(let name), .executing(let name, _), .completed(let name, _, _), .failed(let name, _):
            return name
        }
    }
    
    public var result: String? {
        switch self {
        case .completed(_, _, let result):
            return result
        case .failed(_, let error):
            return error
        default:
            return nil
        }
    }
    
    public var isComplete: Bool {
        switch self {
        case .completed, .failed:
            return true
        default:
            return false
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
