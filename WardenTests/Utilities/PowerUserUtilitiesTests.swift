import XCTest
@testable import Warden

final class PowerUserUtilitiesTests: XCTestCase {
    // MARK: - FuzzyMatcher

    func testFuzzyMatchesSubsequencesCaseAndDiacriticInsensitively() {
        XCTAssertNotNil(FuzzyMatcher.score("swui", in: "SwiftUI layout tips"))
        XCTAssertNotNil(FuzzyMatcher.score("cafe", in: "Café recommendations"))
        XCTAssertNil(FuzzyMatcher.score("xyz", in: "SwiftUI layout tips"))
        XCTAssertNil(FuzzyMatcher.score("tips layout", in: "layout tips"))
    }

    func testFuzzyEmptyQueryMatchesEverything() {
        XCTAssertEqual(FuzzyMatcher.score("", in: "Anything"), 0)
        XCTAssertEqual(FuzzyMatcher.score("   ", in: "Anything"), 0)
    }

    func testFuzzyPrefersContiguousAndWordStartMatches() throws {
        let contiguous = try XCTUnwrap(FuzzyMatcher.score("plan", in: "Trip plan"))
        let scattered = try XCTUnwrap(FuzzyMatcher.score("plan", in: "Pasta, lemon and nuts"))
        XCTAssertGreaterThan(contiguous, scattered)

        let wordStart = try XCTUnwrap(FuzzyMatcher.score("nb", in: "New build"))
        let midWord = try XCTUnwrap(FuzzyMatcher.score("nb", in: "Unable"))
        XCTAssertGreaterThan(wordStart, midWord)
    }

    func testFuzzyPrefersShorterCandidatesOnTies() throws {
        let short = try XCTUnwrap(FuzzyMatcher.score("notes", in: "Notes"))
        let long = try XCTUnwrap(FuzzyMatcher.score("notes", in: "Notes from the long meeting"))
        XCTAssertGreaterThan(short, long)
    }

    // MARK: - QuoteFormatter

    func testBlockquotePrefixesEveryLine() {
        XCTAssertEqual(QuoteFormatter.blockquote("first\nsecond"), "> first\n> second")
        XCTAssertEqual(QuoteFormatter.blockquote("  one\n\ntwo  \n"), "> one\n>\n> two")
    }

    func testMessagePutsQuoteAboveText() {
        XCTAssertEqual(QuoteFormatter.message(quote: "a line", text: "Why?"), "> a line\n\nWhy?")
        XCTAssertEqual(QuoteFormatter.message(quote: "a line", text: "  "), "> a line")
        XCTAssertEqual(QuoteFormatter.message(quote: nil, text: "Plain"), "Plain")
        XCTAssertEqual(QuoteFormatter.message(quote: " \n ", text: "Plain"), "Plain")
    }

    // MARK: - RecentModelsStore

    func testRecentModelsAreNewestFirstDeduplicatedAndLimited() throws {
        let suiteName = "PowerUserUtilitiesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        RecentModelsStore.record(provider: "chatgpt", model: "gpt-4o", defaults: defaults)
        RecentModelsStore.record(provider: "claude", model: "sonnet", defaults: defaults)
        RecentModelsStore.record(provider: "chatgpt", model: "gpt-4o", defaults: defaults)
        RecentModelsStore.record(provider: "", model: "ignored", defaults: defaults)

        XCTAssertEqual(
            RecentModelsStore.all(defaults: defaults),
            [.init(provider: "chatgpt", model: "gpt-4o"), .init(provider: "claude", model: "sonnet")]
        )

        for index in 0..<10 {
            RecentModelsStore.record(provider: "ollama", model: "model-\(index)", defaults: defaults)
        }
        let entries = RecentModelsStore.all(defaults: defaults)
        XCTAssertEqual(entries.count, RecentModelsStore.limit)
        XCTAssertEqual(entries.first?.model, "model-9")
    }

    // MARK: - RetryModelChoices

    func testRetryChoicesSkipCurrentModelUnconfiguredProvidersAndDuplicates() {
        let choices = RetryModelChoices.build(
            favorites: [
                (provider: "claude", model: "sonnet"),
                (provider: "chatgpt", model: "gpt-4o"),
                (provider: "gemini", model: "flash"),
            ],
            recent: [
                .init(provider: "claude", model: "sonnet"),
                .init(provider: "chatgpt", model: "gpt-4o-mini"),
                .init(provider: "chatgpt", model: "gpt-4o"),
            ],
            configuredProviders: ["chatgpt": "OpenAI", "claude": "Anthropic"],
            currentProvider: "chatgpt",
            currentModel: "gpt-4o"
        )

        XCTAssertEqual(choices.favorites.map(\.id), ["claude:sonnet"])
        XCTAssertEqual(choices.favorites.first?.providerName, "Anthropic")
        XCTAssertEqual(choices.recent.map(\.id), ["chatgpt:gpt-4o-mini"])
        XCTAssertFalse(choices.isEmpty)
    }

    func testRetryChoicesEmptyWithoutAlternatives() {
        let choices = RetryModelChoices.build(
            favorites: [(provider: "chatgpt", model: "gpt-4o")],
            recent: [],
            configuredProviders: ["chatgpt": "OpenAI"],
            currentProvider: "chatgpt",
            currentModel: "gpt-4o"
        )
        XCTAssertTrue(choices.isEmpty)
    }
}
