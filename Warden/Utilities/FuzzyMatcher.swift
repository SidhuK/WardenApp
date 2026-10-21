import Foundation

/// Subsequence matching for the quick switcher: every query character must appear in order.
/// Matches at word starts and runs of consecutive characters score higher.
enum FuzzyMatcher {
    static func score(_ query: String, in candidate: String) -> Int? {
        let needle = Array(normalize(query).filter { !$0.isWhitespace })
        guard !needle.isEmpty else { return 0 }
        let haystack = Array(normalize(candidate))
        guard !haystack.isEmpty else { return nil }

        var score = 0
        var queryIndex = 0
        var previousMatch: Int?

        for (index, character) in haystack.enumerated() where queryIndex < needle.count {
            guard character == needle[queryIndex] else { continue }
            score += 1
            if index == 0 {
                score += 10
            } else if !haystack[index - 1].isLetter && !haystack[index - 1].isNumber {
                score += 8
            }
            if let previousMatch, previousMatch == index - 1 {
                score += 5
            }
            previousMatch = index
            queryIndex += 1
        }

        guard queryIndex == needle.count else { return nil }

        let joinedQuery = normalize(query).trimmingCharacters(in: .whitespaces)
        // Greedy matching can scatter a query that also appears whole later on, so reward that strongly.
        if normalize(candidate).contains(joinedQuery) {
            score += 50
        }
        // Prefer shorter candidates when everything else is equal.
        return score * 100 - min(haystack.count, 99)
    }

    private static func normalize(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
