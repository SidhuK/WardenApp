import Foundation
import os

// MARK: - Web Search Service

class WebSearchService {
    private let tavilyService: TavilySearchService
    private let exaService: ExaSearchService
    private static let citationRegex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#, options: [])

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
        guard !urls.isEmpty else {
            return text
        }

        var result = text
        #if DEBUG
        WardenLog.app.debug("[Citations] Converting citations with \(urls.count, privacy: .public) URL(s)")
        #endif

        if let regex = Self.citationRegex {
            let nsString = result as NSString
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: nsString.length))

            var mutableResult = result as NSString

            for match in matches.reversed() {
                guard match.numberOfRanges >= 2 else { continue }
                let fullRange = match.range(at: 0)
                let numberRange = match.range(at: 1)

                let numberString = nsString.substring(with: numberRange)
                guard let number = Int(numberString) else { continue }

                let urlIndex = number - 1
                guard urlIndex >= 0 && urlIndex < urls.count else { continue }

                let start = fullRange.location
                let end = fullRange.location + fullRange.length

                let stringStartIndex = result.startIndex
                let stringEndIndex = result.endIndex

                let startIndex = result.index(stringStartIndex, offsetBy: start)
                let endIndex = result.index(stringStartIndex, offsetBy: end)

                let prevChar: Character? = (startIndex > stringStartIndex)
                    ? result[result.index(before: startIndex)]
                    : nil

                let nextChar: Character? = (endIndex < stringEndIndex)
                    ? result[endIndex]
                    : nil

                guard isCitationBoundary(prevChar), isCitationBoundary(nextChar) else {
                    continue
                }

                let url = urls[urlIndex]
                let replacement = "[\(number)](\(url))"
                mutableResult = mutableResult.replacingCharacters(in: fullRange, with: replacement) as NSString

                #if DEBUG
                WardenLog.app.debug("[Citations] Replaced citation [\(number, privacy: .public)]")
                #endif
            }

            result = mutableResult as String
        } else {
            #if DEBUG
            WardenLog.app.debug("[Citations] Failed to create regex for inline citations")
            #endif
        }

        return result
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

    private func isCitationBoundary(_ ch: Character?) -> Bool {
        guard let ch else { return true }
        if ch.isWhitespace { return true }

        let delimiters: Set<Character> = [".", ",", ";", ":", "!", "?", "(", ")", "[", "]"]
        return delimiters.contains(ch)
    }
}
