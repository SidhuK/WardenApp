
import CoreData
import Foundation
import SwiftUI

struct MessageContent {
    let content: String
    var imageAttachment: ImageAttachment?
    var fileAttachment: FileAttachment?

    // MARK: - Constants
    static let imageTagStart = "<image-uuid>"
    static let imageTagEnd = "</image-uuid>"
    static let fileTagStart = "<file-uuid>"
    static let fileTagEnd = "</file-uuid>"
    
    static let imageRegexPattern = "\(imageTagStart)(.*?)\(imageTagEnd)"
    static let fileRegexPattern = "\(fileTagStart)(.*?)\(fileTagEnd)"

    init(text: String) {
        self.content = text
    }

    init(imageUUID: UUID) {
        self.content = "\(Self.imageTagStart)\(imageUUID.uuidString)\(Self.imageTagEnd)"
    }

    init(imageAttachment: ImageAttachment) {
        self.content = "\(Self.imageTagStart)\(imageAttachment.id.uuidString)\(Self.imageTagEnd)"
        self.imageAttachment = imageAttachment
    }
    
    init(fileUUID: UUID) {
        self.content = "\(Self.fileTagStart)\(fileUUID.uuidString)\(Self.fileTagEnd)"
    }
    
    init(fileAttachment: FileAttachment) {
        self.content = "\(Self.fileTagStart)\(fileAttachment.id.uuidString)\(Self.fileTagEnd)"
        self.fileAttachment = fileAttachment
    }
}

// MARK: - Shared UUID Extraction Utility
private func extractUUIDs(from content: String, pattern: String) -> [UUID] {
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
    let nsString = content as NSString
    let matches = regex.matches(in: content, options: [], range: NSRange(location: 0, length: nsString.length))
    
    return matches.compactMap { match in
        guard match.numberOfRanges > 1 else { return nil }
        let uuidString = nsString.substring(with: match.range(at: 1))
        return UUID(uuidString: uuidString)
    }
}

/// Extension to convert between MessageContent array and string representation
extension Array where Element == MessageContent {
    func toString() -> String {
        map { $0.content }.joined(separator: "\n")
    }

    var textContent: String {
        let pattern = "\(MessageContent.imageRegexPattern)|\(MessageContent.fileRegexPattern)"
        return map { $0.content.replacingOccurrences(of: pattern, with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var imageUUIDs: [UUID] {
        flatMap { extractUUIDs(from: $0.content, pattern: MessageContent.imageRegexPattern) }
    }
    
    var fileUUIDs: [UUID] {
        flatMap { extractUUIDs(from: $0.content, pattern: MessageContent.fileRegexPattern) }
    }
}

extension String {
    func toMessageContents() -> [MessageContent] {
        [MessageContent(text: self)]
    }

    func extractImageUUIDs() -> [UUID] {
        extractUUIDs(from: self, pattern: MessageContent.imageRegexPattern)
    }
    
    func extractFileUUIDs() -> [UUID] {
        extractUUIDs(from: self, pattern: MessageContent.fileRegexPattern)
    }
    
    var containsAttachment: Bool {
        contains(MessageContent.imageTagStart) || contains(MessageContent.fileTagStart)
    }
}
