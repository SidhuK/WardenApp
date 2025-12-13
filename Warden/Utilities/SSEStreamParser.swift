import Foundation

/// Utility for parsing Server-Sent Events (SSE) streams
final class SSEStreamParser {
    enum DeliveryMode {
        /// Buffers multi-line SSE `data:` fields and emits an event when a blank line terminates the event.
        case bufferedEvents
        /// Emits each `data:` line immediately (legacy behavior).
        case lineByLine
        /// Buffers like SSE, but also flushes when payload becomes valid JSON (or `[DONE]`) even without a blank line.
        case bufferedWithCompatibilityFlush
    }
    
    /// Parses an SSE stream and yields data payloads
    /// - Parameters:
    ///   - stream: The async byte stream from URLSession
    ///   - onEvent: Closure called with the data payload string for each event
    static func parse(
        stream: URLSession.AsyncBytes,
        deliveryMode: DeliveryMode = .bufferedWithCompatibilityFlush,
        onEvent: (String) async throws -> Void
    ) async throws {
        var bufferedDataLines: [String] = []
        
        func flushBufferedEvent() async throws {
            guard !bufferedDataLines.isEmpty else { return }
            let payload = bufferedDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            bufferedDataLines.removeAll(keepingCapacity: true)
            guard !payload.isEmpty else { return }
            try await onEvent(payload)
        }
        
        func isValidJSON(_ string: String) -> Bool {
            guard let data = string.data(using: .utf8) else { return false }
            return (try? JSONSerialization.jsonObject(with: data, options: [])) != nil
        }
        
        for try await line in stream.lines {
            // Event terminator
            if line.isEmpty {
                try await flushBufferedEvent()
                continue
            }
            
            // Comment line
            if line.starts(with: ":") {
                continue
            }
            
            // Field parsing: `field:value` (optional single leading space before value).
            let field: Substring
            let value: Substring
            if let colonIndex = line.firstIndex(of: ":") {
                field = Substring(line[..<colonIndex])
                let afterColon = line.index(after: colonIndex)
                if afterColon < line.endIndex, line[afterColon] == " " {
                    value = Substring(line[line.index(after: afterColon)...])
                } else {
                    value = Substring(line[afterColon...])
                }
            } else {
                field = Substring(line)
                value = ""
            }
            
            guard field == "data" else {
                continue
            }
            
            let dataLine = String(value)
            
            switch deliveryMode {
            case .lineByLine:
                let trimmed = dataLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                try await onEvent(trimmed)
                
            case .bufferedEvents:
                bufferedDataLines.append(dataLine)
                
            case .bufferedWithCompatibilityFlush:
                bufferedDataLines.append(dataLine)
                
                let candidate = bufferedDataLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { continue }
                
                if candidate == "[DONE]" || isValidJSON(candidate) {
                    try await flushBufferedEvent()
                }
            }
        }
        
        // Some providers omit the final blank line; flush any trailing buffered data.
        try await flushBufferedEvent()
    }
}
