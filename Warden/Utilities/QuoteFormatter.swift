import Foundation

enum QuoteFormatter {
    /// The text as a Markdown blockquote, one "> " prefixed line per line.
    static func blockquote(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.isEmpty ? ">" : "> \(line)"
            }
            .joined(separator: "\n")
    }

    /// The message to send: the quote as a blockquote above the typed text.
    static func message(quote: String?, text: String) -> String {
        guard let quote, !quote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        let quoted = blockquote(quote)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return quoted }
        return "\(quoted)\n\n\(text)"
    }
}
