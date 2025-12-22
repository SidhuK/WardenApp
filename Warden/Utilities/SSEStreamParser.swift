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

        /// Fast structural check for JSON completeness - avoids expensive JSONSerialization parse
        func looksLikeCompleteJSON(_ string: String) -> Bool {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            
            // Check for balanced braces/brackets as a quick heuristic
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                return true
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                return true
            }
            return false
        }

        func processLine(_ line: String) async throws {
            // Event terminator
            if line.isEmpty {
                try await flushBufferedEvent()
                return
            }

            // Comment line
            if line.starts(with: ":") {
                return
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
                return
            }

            let dataLine = String(value)

            switch deliveryMode {
            case .lineByLine:
                let trimmed = dataLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try await onEvent(trimmed)

            case .bufferedEvents:
                bufferedDataLines.append(dataLine)

            case .bufferedWithCompatibilityFlush:
                bufferedDataLines.append(dataLine)

                let candidate = bufferedDataLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { return }

                if candidate == "[DONE]" || looksLikeCompleteJSON(candidate) {
                    try await flushBufferedEvent()
                }
            }
        }

        // `URLSession.AsyncBytes.lines` may not yield a final unterminated line. Parse by bytes so we don't drop
        // trailing content when a provider omits the last newline.
        var currentLine = Data()
        currentLine.reserveCapacity(4096)

        for try await byte in stream {
            if byte == 0x0A {
                if currentLine.last == 0x0D {
                    currentLine.removeLast()
                }

                if let line = String(data: currentLine, encoding: .utf8) {
                    try await processLine(line)
                }
                currentLine.removeAll(keepingCapacity: true)
                continue
            }

            currentLine.append(byte)
        }

        if !currentLine.isEmpty {
            if currentLine.last == 0x0D {
                currentLine.removeLast()
            }

            if let line = String(data: currentLine, encoding: .utf8) {
                try await processLine(line)
            }
        }

        // Some providers omit the final blank line; flush any trailing buffered data.
        try await flushBufferedEvent()
    }

    static func parse(
        data: Data,
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

        /// Fast structural check for JSON completeness - avoids expensive JSONSerialization parse
        func looksLikeCompleteJSON(_ string: String) -> Bool {
            let trimmed = string.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return false }
            
            // Check for balanced braces/brackets as a quick heuristic
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                return true
            }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                return true
            }
            return false
        }

        func processLine(_ line: String) async throws {
            if line.isEmpty {
                try await flushBufferedEvent()
                return
            }

            if line.starts(with: ":") {
                return
            }

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

            guard field == "data" else { return }

            let dataLine = String(value)

            switch deliveryMode {
            case .lineByLine:
                let trimmed = dataLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                try await onEvent(trimmed)

            case .bufferedEvents:
                bufferedDataLines.append(dataLine)

            case .bufferedWithCompatibilityFlush:
                bufferedDataLines.append(dataLine)

                let candidate = bufferedDataLines.joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !candidate.isEmpty else { return }

                if candidate == "[DONE]" || looksLikeCompleteJSON(candidate) {
                    try await flushBufferedEvent()
                }
            }
        }

        var lineStart = data.startIndex
        for index in data.indices where data[index] == 0x0A {
            var lineData = data[lineStart..<index]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            if let line = String(data: lineData, encoding: .utf8) {
                try await processLine(line)
            }
            lineStart = data.index(after: index)
        }

        if lineStart < data.endIndex {
            var lineData = data[lineStart..<data.endIndex]
            if lineData.last == 0x0D {
                lineData = lineData.dropLast()
            }
            if let line = String(data: lineData, encoding: .utf8) {
                try await processLine(line)
            }
        }

        try await flushBufferedEvent()
    }
}
