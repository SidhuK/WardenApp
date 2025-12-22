import Foundation
import SwiftUI

/// A stateful streaming parser that processes message content incrementally.
/// Unlike MessageParser which re-parses the entire message each time,
/// this parser maintains state and only processes new chunks.
class IncrementalMessageParser {
    
    // MARK: - Types
    
    /// Represents an in-progress block that spans multiple lines
    enum PendingBlock {
        case text([String])
        case code(lang: String, indent: Int, lines: [String])
        case formula([String])
        case thinking([String])
        case table(header: [String], rows: [[String]], headerProcessed: Bool)
    }
    
    // MARK: - State
    
    /// Elements that have been finalized and won't change
    private var completedElements: [MessageElements] = []
    
    /// Current block being accumulated (may span multiple chunks)
    private var pendingBlock: PendingBlock? = nil
    
    /// Partial line waiting for newline character
    private var unparsedTail: String = ""
    
    /// Color scheme for any parsing that needs it
    let colorScheme: ColorScheme
    
    // MARK: - Initialization
    
    init(colorScheme: ColorScheme) {
        self.colorScheme = colorScheme
    }
    
    // MARK: - Public API
    
    /// Append a new chunk from the streaming response.
    /// Returns the newly completed elements (delta).
    @discardableResult
    func appendChunk(_ chunk: String) -> [MessageElements] {
        let previousCount = completedElements.count
        
        // Combine with any leftover partial line
        let combined = unparsedTail + chunk
        
        // Split by newlines, keeping track of whether chunk ends with newline
        let endsWithNewline = combined.hasSuffix("\n")
        var lines = combined.split(separator: "\n", omittingEmptySubsequences: false).map { String($0) }
        
        // If doesn't end with newline, last element is partial - save for later
        if !endsWithNewline && !lines.isEmpty {
            unparsedTail = lines.removeLast()
        } else {
            unparsedTail = ""
        }
        
        // Process each complete line
        for line in lines {
            processLine(line)
        }
        
        // Return newly completed elements
        return Array(completedElements.dropFirst(previousCount))
    }
    
    /// Finalize parsing - flush any pending blocks.
    /// Call this when streaming ends.
    func finalize() -> [MessageElements] {
        // Process any remaining tail as a line
        if !unparsedTail.isEmpty {
            processLine(unparsedTail)
            unparsedTail = ""
        }
        
        // Flush pending block
        finalizePendingBlock()
        
        return completedElements
    }
    
    /// Get all elements including pending block rendered as temporary.
    /// Use this for UI display during streaming.
    func getAllElements() -> [MessageElements] {
        var result = completedElements
        
        // Add pending block as a temporary element
        if let pending = pendingBlock {
            if let element = renderPendingBlock(pending) {
                result.append(element)
            }
        }
        
        // Add unparsed tail as text if non-empty
        if !unparsedTail.isEmpty {
            // Append to last text element if possible, or create new
            if case .text(let existingText) = result.last {
                result.removeLast()
                result.append(.text(existingText + "\n" + unparsedTail))
            } else {
                result.append(.text(unparsedTail))
            }
        }
        
        return result
    }
    
    /// Reset parser state for a new streaming session
    func reset() {
        completedElements = []
        pendingBlock = nil
        unparsedTail = ""
    }
    
    // MARK: - Private Implementation
    
    private func processLine(_ line: String) {
        let blockType = detectBlockType(line: line)
        
        switch blockType {
        case .codeBlock:
            handleCodeBlockMarker(line: line)
            
        case .table:
            handleTableLine(line: line)
            
        case .formulaBlock:
            finalizePendingBlock()
            pendingBlock = .formula([])
            
        case .formulaLine:
            handleFormulaLine(line: line)
            
        case .thinking:
            handleThinkingLine(line: line)
            
        case .imageUUID:
            if let uuid = extractImageUUID(line) {
                finalizePendingBlock()
                completedElements.append(.image(uuid))
            } else {
                appendTextLine(line)
            }
            
        case .fileUUID:
            if let uuid = extractFileUUID(line) {
                finalizePendingBlock()
                completedElements.append(.file(uuid))
            } else {
                appendTextLine(line)
            }
            
        case .text:
            handleTextLine(line: line)
        }
    }
    
    // MARK: - Block Type Detection (reused from MessageParser)
    
    private enum BlockType {
        case text, table, codeBlock, formulaBlock, formulaLine, thinking, imageUUID, fileUUID
    }
    
    private func detectBlockType(line: String) -> BlockType {
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        
        if trimmedLine.hasPrefix("<think>") || trimmedLine.hasPrefix("</think>") {
            return .thinking
        } else if trimmedLine.hasPrefix("```") {
            return .codeBlock
        } else if trimmedLine.first == "|" {
            return .table
        } else if trimmedLine.hasPrefix("\\[") {
            return trimmedLine.replacingOccurrences(of: " ", with: "") == "\\[" ? .formulaBlock : .formulaLine
        } else if trimmedLine.hasPrefix("\\]") {
            return .formulaLine
        } else if trimmedLine.hasPrefix("<image-uuid>") {
            return .imageUUID
        } else if trimmedLine.hasPrefix("<file-uuid>") {
            return .fileUUID
        } else {
            return .text
        }
    }
    
    // MARK: - Block Handlers
    
    private func handleCodeBlockMarker(line: String) {
        if case .code(_, _, let lines) = pendingBlock {
            // Closing marker - finalize code block
            let lang = extractCodeLanguage(from: pendingBlock)
            let indent = extractCodeIndent(from: pendingBlock)
            let combinedCode = lines.joined(separator: "\n")
            completedElements.append(.code(code: combinedCode, lang: lang, indent: indent))
            pendingBlock = nil
        } else {
            // Opening marker
            finalizePendingBlock()
            let indent = line.count - line.trimmingCharacters(in: .whitespaces).count
            let lang = line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "```", with: "")
            pendingBlock = .code(lang: lang, indent: indent, lines: [])
        }
    }
    
    private func handleTableLine(line: String) {
        let rowData = parseTableRow(line: line)
        
        // Skip delimiter rows
        if rowData.allSatisfy({ $0.allSatisfy({ $0 == "-" || $0 == ":" }) }) {
            return
        }
        
        if case .table(let header, var rows, let headerProcessed) = pendingBlock {
            if !headerProcessed {
                // This is actually the header row
                pendingBlock = .table(header: rowData, rows: rows, headerProcessed: true)
            } else {
                rows.append(rowData)
                pendingBlock = .table(header: header, rows: rows, headerProcessed: true)
            }
        } else {
            // Start new table
            finalizePendingBlock()
            pendingBlock = .table(header: rowData, rows: [], headerProcessed: false)
        }
    }
    
    private func handleFormulaLine(line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        
        if trimmed.hasPrefix("\\]") {
            // Closing formula
            if case .formula(let lines) = pendingBlock {
                let combined = lines.joined(separator: "\n")
                completedElements.append(.formula(combined))
                pendingBlock = nil
            }
        } else {
            // Add to formula
            let formulaContent = line
                .replacingOccurrences(of: "\\[", with: "")
                .replacingOccurrences(of: "\\]", with: "")
            
            if case .formula(var lines) = pendingBlock {
                lines.append(formulaContent)
                pendingBlock = .formula(lines)
            } else {
                // Single-line formula
                finalizePendingBlock()
                completedElements.append(.formula(formulaContent))
            }
        }
    }
    
    private func handleThinkingLine(line: String) {
        if line.contains("</think>") {
            // Closing or single-line thinking
            if case .thinking(var lines) = pendingBlock {
                let lastLine = line.replacingOccurrences(of: "</think>", with: "")
                if !lastLine.isEmpty {
                    lines.append(lastLine)
                }
                let combined = lines.joined(separator: "\n")
                    .replacingOccurrences(of: "<think>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completedElements.append(.thinking(combined, isExpanded: false))
                pendingBlock = nil
            } else if line.contains("<think>") {
                // Single line: <think>...</think>
                finalizePendingBlock()
                let content = line
                    .replacingOccurrences(of: "<think>", with: "")
                    .replacingOccurrences(of: "</think>", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completedElements.append(.thinking(content, isExpanded: false))
            }
        } else if line.contains("<think>") {
            // Opening thinking block
            finalizePendingBlock()
            let firstLine = line.replacingOccurrences(of: "<think>", with: "")
            pendingBlock = .thinking(firstLine.isEmpty ? [] : [firstLine])
        }
    }
    
    private func handleTextLine(line: String) {
        // Check if we're inside a special block
        switch pendingBlock {
        case .thinking(var lines):
            if line.contains("</think>") {
                let lastLine = line.replacingOccurrences(of: "</think>", with: "")
                if !lastLine.isEmpty {
                    lines.append(lastLine)
                }
                let combined = lines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                completedElements.append(.thinking(combined, isExpanded: false))
                pendingBlock = nil
            } else {
                lines.append(line)
                pendingBlock = .thinking(lines)
            }
            
        case .code(let lang, let indent, var lines):
            // Add line to code block (remove leading indent if present)
            let adjustedLine = indent > 0 && line.count >= indent ? String(line.dropFirst(indent)) : line
            lines.append(adjustedLine)
            pendingBlock = .code(lang: lang, indent: indent, lines: lines)
            
        case .formula(var lines):
            let formulaContent = line
                .replacingOccurrences(of: "\\[", with: "")
                .replacingOccurrences(of: "\\]", with: "")
            lines.append(formulaContent)
            pendingBlock = .formula(lines)
            
        case .table:
            // Non-table line ends the table
            finalizePendingBlock()
            appendTextLine(line)
            
        case .text(var lines):
            lines.append(line)
            pendingBlock = .text(lines)
            
        case nil:
            pendingBlock = .text([line])
        }
    }
    
    private func appendTextLine(_ line: String) {
        if case .text(var lines) = pendingBlock {
            lines.append(line)
            pendingBlock = .text(lines)
        } else {
            finalizePendingBlock()
            pendingBlock = .text([line])
        }
    }
    
    // MARK: - Finalization
    
    private func finalizePendingBlock() {
        guard let pending = pendingBlock else { return }
        
        switch pending {
        case .text(let lines):
            if !lines.isEmpty {
                let combined = lines.joined(separator: "\n")
                completedElements.append(.text(combined))
            }
            
        case .code(let lang, let indent, let lines):
            let combinedCode = lines.joined(separator: "\n")
            completedElements.append(.code(code: combinedCode, lang: lang, indent: indent))
            
        case .formula(let lines):
            let combined = lines.joined(separator: "\n")
            completedElements.append(.formula(combined))
            
        case .thinking(let lines):
            let combined = lines.joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !combined.isEmpty {
                completedElements.append(.thinking(combined, isExpanded: false))
            }
            
        case .table(let header, let rows, _):
            if !header.isEmpty {
                completedElements.append(.table(header: header, data: rows))
            }
        }
        
        pendingBlock = nil
    }
    
    private func renderPendingBlock(_ pending: PendingBlock) -> MessageElements? {
        switch pending {
        case .text(let lines):
            guard !lines.isEmpty else { return nil }
            return .text(lines.joined(separator: "\n"))
            
        case .code(let lang, let indent, let lines):
            return .code(code: lines.joined(separator: "\n"), lang: lang, indent: indent)
            
        case .formula(let lines):
            return .formula(lines.joined(separator: "\n"))
            
        case .thinking(let lines):
            let combined = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !combined.isEmpty else { return nil }
            return .thinking(combined, isExpanded: false)
            
        case .table(let header, let rows, _):
            guard !header.isEmpty else { return nil }
            return .table(header: header, data: rows)
        }
    }
    
    // MARK: - Helpers
    
    private func extractCodeLanguage(from block: PendingBlock?) -> String {
        if case .code(let lang, _, _) = block {
            return lang
        }
        return ""
    }
    
    private func extractCodeIndent(from block: PendingBlock?) -> Int {
        if case .code(_, let indent, _) = block {
            return indent
        }
        return 0
    }
    
    private func parseTableRow(line: String) -> [String] {
        return line.split(separator: "|")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func extractImageUUID(_ line: String) -> UUID? {
        let pattern = "<image-uuid>(.*?)</image-uuid>"
        if let range = line.range(of: pattern, options: .regularExpression) {
            let uuidString = String(line[range])
                .replacingOccurrences(of: "<image-uuid>", with: "")
                .replacingOccurrences(of: "</image-uuid>", with: "")
            return UUID(uuidString: uuidString)
        }
        return nil
    }
    
    private func extractFileUUID(_ line: String) -> UUID? {
        let pattern = "<file-uuid>(.*?)</file-uuid>"
        if let range = line.range(of: pattern, options: .regularExpression) {
            let uuidString = String(line[range])
                .replacingOccurrences(of: "<file-uuid>", with: "")
                .replacingOccurrences(of: "</file-uuid>", with: "")
            return UUID(uuidString: uuidString)
        }
        return nil
    }
}
