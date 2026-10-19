import Foundation

struct ReasoningStep: Equatable {
    let title: String?
    let body: String
}

/// Splits a model's reasoning text into titled steps for the expanded reasoning view.
enum ReasoningStepParser {
    static let maxDerivedTitleLength = 60

    static func parse(_ text: String) -> [ReasoningStep] {
        let normalized =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard !normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        let lines = normalized.components(separatedBy: "\n")
        if let steps = stepsFromHeadings(lines) {
            return steps
        }

        let paragraphs = splitParagraphs(lines)
        guard paragraphs.count > 1 else {
            return [ReasoningStep(title: nil, body: normalized.trimmingCharacters(in: .whitespacesAndNewlines))]
        }
        return paragraphs.map { ReasoningStep(title: derivedTitle(from: $0), body: $0) }
    }

    // MARK: - Headings

    /// Returns nil when the text has no heading lines outside code fences.
    private static func stepsFromHeadings(_ lines: [String]) -> [ReasoningStep]? {
        var steps: [ReasoningStep] = []
        var currentTitle: String?
        var currentLines: [String] = []
        var foundHeading = false
        var inFence = false

        func flush() {
            let body = currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if currentTitle != nil || !body.isEmpty {
                steps.append(ReasoningStep(title: currentTitle, body: body))
            }
        }

        for line in lines {
            if isFenceDelimiter(line) {
                inFence.toggle()
            }
            else if !inFence, let title = headingTitle(line) {
                flush()
                foundHeading = true
                currentTitle = title
                currentLines = []
                continue
            }
            currentLines.append(line)
        }
        guard foundHeading else { return nil }
        flush()
        return steps
    }

    /// Title of a line that is a whole-line bold heading (`**Title**`, `**Title:**`, `**Title**:`) or a
    /// Markdown heading of level 1-3; nil for anything else.
    static func headingTitle(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("#") {
            let hashes = trimmed.prefix { $0 == "#" }.count
            guard (1...3).contains(hashes) else { return nil }
            let rest = trimmed.dropFirst(hashes)
            guard rest.first == " " else { return nil }
            var title = rest.trimmingCharacters(in: .whitespaces)
            while title.hasSuffix("#") {
                title.removeLast()
            }
            return cleanedTitle(title)
        }

        guard trimmed.hasPrefix("**") else { return nil }
        var inner = trimmed.dropFirst(2)
        if inner.hasSuffix("**:") {
            inner = inner.dropLast(3)
        }
        else if inner.hasSuffix("**") {
            inner = inner.dropLast(2)
        }
        else {
            return nil
        }
        guard !inner.contains("**") else { return nil }
        return cleanedTitle(String(inner))
    }

    private static func cleanedTitle(_ raw: String) -> String? {
        var title = raw.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
        while title.hasSuffix(":") {
            title.removeLast()
            title = title.trimmingCharacters(in: .whitespaces)
        }
        return title.isEmpty ? nil : title
    }

    private static func isFenceDelimiter(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
    }

    // MARK: - Paragraphs

    private static func splitParagraphs(_ lines: [String]) -> [String] {
        var paragraphs: [String] = []
        var current: [String] = []
        var inFence = false

        func flush() {
            let paragraph = current.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !paragraph.isEmpty {
                paragraphs.append(paragraph)
            }
            current = []
        }

        for line in lines {
            if isFenceDelimiter(line) {
                inFence.toggle()
            }
            if !inFence, line.trimmingCharacters(in: .whitespaces).isEmpty {
                flush()
            }
            else {
                current.append(line)
            }
        }
        flush()
        return paragraphs
    }

    /// Short title from the paragraph's first sentence, with inline Markdown removed.
    static func derivedTitle(from paragraph: String) -> String? {
        let flattened =
            paragraph
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "#>-*• ").union(.whitespaces))
        guard !flattened.isEmpty else { return nil }

        var firstSentence = flattened
        flattened.enumerateSubstrings(in: flattened.startIndex..., options: .bySentences) { substring, _, _, stop in
            if let sentence = substring?.trimmingCharacters(in: .whitespaces), !sentence.isEmpty {
                firstSentence = sentence
                stop = true
            }
        }

        while let last = firstSentence.last, ".:;,".contains(last) {
            firstSentence.removeLast()
        }
        firstSentence = firstSentence.trimmingCharacters(in: .whitespaces)
        guard !firstSentence.isEmpty else { return nil }
        return truncated(firstSentence)
    }

    private static func truncated(_ text: String) -> String {
        guard text.count > maxDerivedTitleLength else { return text }
        let limit = text.prefix(maxDerivedTitleLength - 1)
        var cut = limit
        let endsOnWordBoundary = text[limit.endIndex].isWhitespace
        if !endsOnWordBoundary, let lastSpace = limit.lastIndex(of: " "),
            limit.distance(from: limit.startIndex, to: lastSpace) > 20
        {
            cut = limit[..<lastSpace]
        }
        return cut.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters)) + "…"
    }
}
