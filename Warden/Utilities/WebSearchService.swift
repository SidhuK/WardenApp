import Foundation
import os

// MARK: - Web Search Service

class WebSearchService {
    private let tavilyService: TavilySearchService
    private let exaService: ExaSearchService

    init(
        tavilyService: TavilySearchService = TavilySearchService(),
        exaService: ExaSearchService = ExaSearchService()
    ) {
        self.tavilyService = tavilyService
        self.exaService = exaService
    }

    func performSearch(
        query: String,
        onStatusUpdate: @MainActor @escaping (SearchStatus) -> Void
    ) async throws -> (context: String, urls: [String], sources: [SearchSource]) {
        #if DEBUG
        WardenLog.app.debug("[WebSearch] performSearch called")
        #endif

        await onStatusUpdate(.searching(query: query))

        let provider = WebSearchProvider.selected
        let maxResults = UserDefaults.standard.integer(forKey: AppConstants.webSearchMaxResultsKey)
        let resultsLimit = maxResults > 0 ? maxResults : AppConstants.webSearchDefaultMaxResults

        #if DEBUG
        WardenLog.app.debug(
            "[WebSearch] Provider=\(provider.displayName, privacy: .public), maxResults=\(resultsLimit, privacy: .public)"
        )
        #endif

        await onStatusUpdate(.fetchingResults(sources: resultsLimit))

        switch provider {
        case .tavily:
            return try await performTavilySearch(
                query: query,
                resultsLimit: resultsLimit,
                onStatusUpdate: onStatusUpdate
            )
        case .exa:
            return try await performExaSearch(
                query: query,
                resultsLimit: resultsLimit,
                onStatusUpdate: onStatusUpdate
            )
        }
    }

    func isSearchCommand(_ message: String) -> (isSearch: Bool, query: String?) {
        for prefix in AppConstants.searchCommandAliases {
            if message.lowercased().hasPrefix(prefix) {
                let query = message.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
                return (true, query.isEmpty ? nil : query)
            }
        }
        return (false, nil)
    }

    func convertCitationsToLinks(_ text: String, urls: [String]) -> String {
        InlineCitations.convertToLinks(text, urls: urls)
    }

    private func performTavilySearch(
        query: String,
        resultsLimit: Int,
        onStatusUpdate: @MainActor @escaping (SearchStatus) -> Void
    ) async throws -> (context: String, urls: [String], sources: [SearchSource]) {
        let searchDepth = UserDefaults.standard.string(forKey: AppConstants.tavilySearchDepthKey)
            ?? AppConstants.tavilyDefaultSearchDepth
        let includeAnswer = UserDefaults.standard.object(forKey: AppConstants.tavilyIncludeAnswerKey) == nil
            ? true
            : UserDefaults.standard.bool(forKey: AppConstants.tavilyIncludeAnswerKey)

        #if DEBUG
        WardenLog.app.debug(
            "[WebSearch] Tavily settings depth=\(searchDepth, privacy: .public), includeAnswer=\(includeAnswer, privacy: .public)"
        )
        #endif

        let response = try await tavilyService.search(
            query: query,
            searchDepth: searchDepth,
            maxResults: resultsLimit,
            includeAnswer: includeAnswer
        )

        #if DEBUG
        WardenLog.app.debug("[WebSearch] Received \(response.results.count, privacy: .public) Tavily result(s)")
        #endif

        await onStatusUpdate(.processingResults)

        let sources = response.results.map { result in
            SearchSource(
                title: result.title,
                url: result.url,
                score: result.score,
                publishedDate: result.publishedDate
            )
        }

        await onStatusUpdate(.completed(sources: sources))

        let urls = response.results.map { $0.url }
        let context = tavilyService.formatResultsForContext(response)

        return (context, urls, sources)
    }

    private func performExaSearch(
        query: String,
        resultsLimit: Int,
        onStatusUpdate: @MainActor @escaping (SearchStatus) -> Void
    ) async throws -> (context: String, urls: [String], sources: [SearchSource]) {
        let searchType = UserDefaults.standard.string(forKey: AppConstants.exaSearchTypeKey)
            ?? AppConstants.exaDefaultSearchType

        #if DEBUG
        WardenLog.app.debug("[WebSearch] Exa settings type=\(searchType, privacy: .public)")
        #endif

        let response = try await exaService.search(
            query: query,
            searchType: searchType,
            maxResults: resultsLimit
        )

        #if DEBUG
        WardenLog.app.debug("[WebSearch] Received \(response.results.count, privacy: .public) Exa result(s)")
        #endif

        await onStatusUpdate(.processingResults)

        let sources = response.results.map { result in
            SearchSource(
                title: result.title,
                url: result.url,
                score: 0,
                publishedDate: result.publishedDate
            )
        }

        await onStatusUpdate(.completed(sources: sources))

        let urls = response.results.map { $0.url }
        let context = exaService.formatResultsForContext(response, query: query)

        return (context, urls, sources)
    }
}

// MARK: - Inline Citations

/// Pure helpers for `[n]` citations in web-search replies. Citation `n` refers to `sources[n - 1]`,
/// the same numbering as the source chips under the reply.
enum InlineCitations {
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#, options: [])
    private static let inlineCodeRegex = try? NSRegularExpression(pattern: "`[^`\\n]+`", options: [])
    private static let boundaryDelimiters: Set<Character> = [".", ",", ";", ":", "!", "?", "(", ")", "[", "]"]

    /// Rewrites standalone `[n]` markers into `[n](urls[n - 1])` Markdown links.
    /// Markers inside fenced code blocks or inline code, out-of-range numbers and markers that are
    /// already link text (`[n](...)`) are left untouched.
    static func convertToLinks(_ text: String, urls: [String]) -> String {
        guard !urls.isEmpty, text.contains("["), let regex = citationRegex else {
            return text
        }

        let nsText = text as NSString
        let protectedRanges = codeRanges(in: text)
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
        let result = NSMutableString(string: text)

        for match in matches.reversed() {
            let fullRange = match.range(at: 0)
            guard let number = Int(nsText.substring(with: match.range(at: 1))),
                  number >= 1, number <= urls.count,
                  !protectedRanges.contains(where: { NSIntersectionRange($0, fullRange).length > 0 }),
                  let swiftRange = Range(fullRange, in: text)
            else {
                continue
            }

            let previous = swiftRange.lowerBound > text.startIndex
                ? text[text.index(before: swiftRange.lowerBound)]
                : nil
            let next = swiftRange.upperBound < text.endIndex ? text[swiftRange.upperBound] : nil
            guard isBoundary(previous), isBoundary(next), next != "(" else { continue }

            result.replaceCharacters(in: fullRange, with: "[\(number)](\(urls[number - 1]))")
        }

        return result as String
    }

    /// Returns the index into `sources` that a Markdown link in a web-search reply cites, or nil when the
    /// link isn't a citation and should render as a normal link.
    ///
    /// A link counts as a citation when its text is a number (`[2](url)`, Perplexity-style `[[2]](url)`) or
    /// the destination's domain (`[nytimes.com](url)`, which OpenRouter's web plugin emits), and its
    /// destination is one of the sources. The returned index follows the sources order so the rendered
    /// number always matches the chips, even if the model's own number disagrees.
    static func sourceIndex(linkText: String, destination: String, sources: [SearchSource]) -> Int? {
        guard !sources.isEmpty else { return nil }

        var label = linkText.trimmingCharacters(in: .whitespaces)
        if label.hasPrefix("["), label.hasSuffix("]"), label.count > 2 {
            label = String(label.dropFirst().dropLast())
        }

        let target = normalizedURL(destination)
        let number = Int(label)
        if let number, number >= 1, number <= sources.count,
           normalizedURL(sources[number - 1].url) == target {
            return number - 1
        }

        let isCitationLabel = number != nil || label.lowercased() == domain(of: destination)
        guard isCitationLabel else { return nil }
        return sources.firstIndex { normalizedURL($0.url) == target }
    }

    /// Fenced code blocks and inline code spans, in UTF-16 offsets.
    static func codeRanges(in text: String) -> [NSRange] {
        let nsText = text as NSString
        var ranges: [NSRange] = []
        var fenceStart: Int?
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                if let start = fenceStart {
                    ranges.append(NSRange(location: start, length: NSMaxRange(lineRange) - start))
                    fenceStart = nil
                } else {
                    fenceStart = lineRange.location
                }
            }
            location = NSMaxRange(lineRange)
        }
        if let start = fenceStart {
            ranges.append(NSRange(location: start, length: nsText.length - start))
        }

        if let regex = inlineCodeRegex {
            let fenced = ranges
            for match in regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsText.length))
            where !fenced.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                ranges.append(match.range)
            }
        }
        return ranges
    }

    static func domain(of url: String) -> String? {
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Compares URLs loosely: ignores scheme, `www.`, host case, fragment and a trailing slash.
    private static func normalizedURL(_ url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let host = components.host else {
            return trimmed
        }
        components.fragment = nil
        let lowerHost = host.lowercased()
        let bareHost = lowerHost.hasPrefix("www.") ? String(lowerHost.dropFirst(4)) : lowerHost
        var path = components.percentEncodedPath
        if path.hasSuffix("/") { path.removeLast() }
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return bareHost + path + query
    }

    private static func isBoundary(_ character: Character?) -> Bool {
        guard let character else { return true }
        return character.isWhitespace || boundaryDelimiters.contains(character)
    }
}
