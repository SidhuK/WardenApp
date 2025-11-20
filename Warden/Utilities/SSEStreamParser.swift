import Foundation

/// Utility for parsing Server-Sent Events (SSE) streams
class SSEStreamParser {
    
    /// Parses an SSE stream and yields data payloads
    /// - Parameters:
    ///   - stream: The async byte stream from URLSession
    ///   - onEvent: Closure called with the data payload string for each event
    static func parse(
        stream: URLSession.AsyncBytes,
        onEvent: (String) async throws -> Void
    ) async throws {
        for try await line in stream.lines {
            // Skip empty lines and comments
            guard !line.isEmpty, !line.starts(with: ":") else { continue }
            
            if line.starts(with: "data: ") {
                let data = line.dropFirst(6).trimmingCharacters(in: .whitespacesAndNewlines)
                if !data.isEmpty {
                    try await onEvent(data)
                }
            }
        }
    }
}
