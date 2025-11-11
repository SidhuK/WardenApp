
import CoreData
import Foundation
import SwiftUI

struct MessageContent {
    let content: String
    var imageAttachment: ImageAttachment?
    var fileAttachment: FileAttachment?

    init(text: String) {
        self.content = text
    }

    init(imageUUID: UUID) {
        self.content = "<image-uuid>\(imageUUID.uuidString)</image-uuid>"
    }

    init(imageAttachment: ImageAttachment) {
        self.content = "<image-uuid>\(imageAttachment.id.uuidString)</image-uuid>"
        self.imageAttachment = imageAttachment
    }
    
    init(fileUUID: UUID) {
        self.content = "<file-uuid>\(fileUUID.uuidString)</file-uuid>"
    }
    
    init(fileAttachment: FileAttachment) {
        self.content = "<file-uuid>\(fileAttachment.id.uuidString)</file-uuid>"
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
        map { $0.content.replacingOccurrences(of: "<image-uuid>.*?</image-uuid>|<file-uuid>.*?</file-uuid>", with: "", options: .regularExpression) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var imageUUIDs: [UUID] {
        flatMap { extractUUIDs(from: $0.content, pattern: "<image-uuid>(.*?)</image-uuid>") }
    }
    
    var fileUUIDs: [UUID] {
        flatMap { extractUUIDs(from: $0.content, pattern: "<file-uuid>(.*?)</file-uuid>") }
    }
}

extension String {
    func toMessageContents() -> [MessageContent] {
        [MessageContent(text: self)]
    }

    func extractImageUUIDs() -> [UUID] {
        extractUUIDs(from: self, pattern: "<image-uuid>(.*?)</image-uuid>")
    }
    
    func extractFileUUIDs() -> [UUID] {
        extractUUIDs(from: self, pattern: "<file-uuid>(.*?)</file-uuid>")
    }
}
