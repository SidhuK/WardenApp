import CoreData
import XCTest
@testable import Warden

@MainActor
final class PromptLibraryManagerTests: XCTestCase {
    private var container: NSPersistentContainer!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!
    private var library: PromptLibraryManager!

    override func setUp() async throws {
        // Reuse the app's loaded model so PromptEntity maps to a single entity description.
        let model = PersistenceController.shared.container.managedObjectModel
        container = NSPersistentContainer(name: "PromptLibraryTests", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        defaultsSuiteName = "PromptLibraryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        library = PromptLibraryManager(context: container.viewContext, userDefaults: defaults)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        library = nil
        container = nil
    }

    @discardableResult
    private func add(_ name: String, shortcut: String?, uses: Int64 = 0, lastUsed: Date? = nil) throws -> PromptEntity {
        let prompt = try XCTUnwrap(library.addPrompt(name: name, content: "\(name) content", shortcut: shortcut))
        prompt.usageCount = uses
        prompt.lastUsedDate = lastUsed
        try container.viewContext.save()
        return prompt
    }

    func testShortcutPrefixRanksAboveNameAndContainsMatches() throws {
        try add("Resummarize notes", shortcut: "notes", uses: 50)
        try add("Summary", shortcut: "tldr", uses: 10)
        try add("Summarize", shortcut: "sum", uses: 0)

        let names = library.prompts(matching: "sum").map(\.name)
        XCTAssertEqual(names, ["Summarize", "Summary", "Resummarize notes"])
    }

    func testQueryIgnoresLeadingSlashAndCase() throws {
        try add("Explain", shortcut: "explain")
        XCTAssertEqual(library.prompts(matching: "/EXP").map(\.name), ["Explain"])
    }

    func testSameTierRankedByUsageThenRecency() throws {
        let now = Date()
        try add("Fix A", shortcut: "fix-a", uses: 2, lastUsed: now.addingTimeInterval(-100))
        try add("Fix B", shortcut: "fix-b", uses: 5, lastUsed: now.addingTimeInterval(-1000))
        try add("Fix C", shortcut: "fix-c", uses: 2, lastUsed: now)

        XCTAssertEqual(library.prompts(matching: "fix").map(\.name), ["Fix B", "Fix C", "Fix A"])
    }

    func testFuzzySubsequenceMatchAndNoMatch() throws {
        try add("Code review", shortcut: "review")
        XCTAssertEqual(library.prompts(matching: "cdrv").map(\.name), ["Code review"])
        XCTAssertTrue(library.prompts(matching: "zzz").isEmpty)
    }

    func testEmptyQueryAndTopPromptsUseUsageOrder() throws {
        try add("A", shortcut: "a", uses: 1)
        try add("B", shortcut: "b", uses: 3)
        try add("C", shortcut: "c", uses: 2)

        XCTAssertEqual(library.prompts(matching: "").map(\.name), ["B", "C", "A"])
        XCTAssertEqual(library.topPrompts(limit: 2).map(\.name), ["B", "C"])
        XCTAssertEqual(library.prompts(matching: "", limit: 1).map(\.name), ["B"])
    }

    func testRecordUseBumpsCountAndDate() throws {
        let prompt = try add("Translate", shortcut: "translate")
        library.recordUse(prompt)
        library.recordUse(prompt)
        XCTAssertEqual(prompt.usageCount, 2)
        XCTAssertNotNil(prompt.lastUsedDate)
    }

    func testShortcutNormalization() {
        XCTAssertEqual(PromptLibraryManager.normalizedShortcut("/Fix Grammar "), "fix-grammar")
        XCTAssertNil(PromptLibraryManager.normalizedShortcut("  / "))
        XCTAssertNil(PromptLibraryManager.normalizedShortcut(nil))
    }

    func testSeedDefaultsRunsOnce() throws {
        library.seedDefaultsIfNeeded()
        XCTAssertEqual(library.allPrompts().count, PromptLibraryManager.defaultPrompts.count)
        XCTAssertEqual(
            Set(library.allPrompts().compactMap(\.shortcut)),
            ["summarize", "translate", "fix", "explain", "review"]
        )

        for prompt in library.allPrompts() { library.deletePrompt(prompt) }
        library.seedDefaultsIfNeeded()
        XCTAssertTrue(library.allPrompts().isEmpty)
    }

    func testCompletionStateAcceptReplacesQueryAndRecordsUse() throws {
        let prompt = try add("Summarize", shortcut: "summarize")
        let state = PromptCompletionState(library: library)

        state.update(for: "/sum")
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.accept(), "Summarize content")
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(prompt.usageCount, 1)
    }

    func testCompletionStateEscapeKeepsMenuClosedUntilTextChanges() throws {
        try add("Summarize", shortcut: "summarize")
        try add("Summary", shortcut: "summary")
        let state = PromptCompletionState(library: library)

        state.update(for: "/su")
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 1)
        state.moveSelection(by: 1)
        XCTAssertEqual(state.selectedIndex, 0)

        state.dismiss(currentText: "/su")
        state.update(for: "/su")
        XCTAssertFalse(state.isVisible)

        state.update(for: "/sum")
        XCTAssertTrue(state.isVisible)
    }
}

final class SlashQueryDetectionTests: XCTestCase {
    func testDetection() {
        XCTAssertEqual(PromptCompletionState.slashQuery(in: "/"), "")
        XCTAssertEqual(PromptCompletionState.slashQuery(in: "/sum"), "sum")
        XCTAssertNil(PromptCompletionState.slashQuery(in: "/sum x"))
        XCTAssertNil(PromptCompletionState.slashQuery(in: "a /sum"))
        XCTAssertNil(PromptCompletionState.slashQuery(in: "/sum\nmore"))
        XCTAssertNil(PromptCompletionState.slashQuery(in: "hello\n/sum"))
        XCTAssertNil(PromptCompletionState.slashQuery(in: ""))
        XCTAssertNil(PromptCompletionState.slashQuery(in: " /sum"))
    }
}

final class ContextUsageEstimatorTests: XCTestCase {
    private typealias Sample = ContextUsageEstimator.MessageSample

    func testCharacterEstimateRoundsUp() {
        XCTAssertEqual(ContextUsageEstimator.estimatedTokens(forCharacterCount: 0), 0)
        XCTAssertEqual(ContextUsageEstimator.estimatedTokens(forCharacterCount: 1), 1)
        XCTAssertEqual(ContextUsageEstimator.estimatedTokens(forCharacterCount: 8), 2)
        XCTAssertEqual(ContextUsageEstimator.estimatedTokens(forCharacterCount: 9), 3)
    }

    func testFallbackEstimatesEveryMessageSystemPromptAndComposer() {
        let messages = [
            Sample(characterCount: 400, isAssistant: false, usage: nil),
            Sample(characterCount: 800, isAssistant: true, usage: nil),
        ]
        let tokens = ContextUsageEstimator.estimatedTokens(
            messages: messages,
            systemPromptCharacters: 40,
            composerCharacters: 20
        )
        XCTAssertEqual(tokens, 100 + 200 + 10 + 5)
    }

    func testUsesLastAssistantUsageAndEstimatesOnlyLaterMessages() {
        let messages = [
            Sample(characterCount: 40_000, isAssistant: false, usage: nil),
            Sample(characterCount: 400, isAssistant: true, usage: TokenUsage(inputTokens: 1_000, outputTokens: 50)),
            Sample(characterCount: 4_000, isAssistant: false, usage: nil),
            Sample(characterCount: 400, isAssistant: true, usage: TokenUsage(inputTokens: 12_000, outputTokens: 400)),
            Sample(characterCount: 80, isAssistant: false, usage: nil),
        ]
        let tokens = ContextUsageEstimator.estimatedTokens(
            messages: messages,
            systemPromptCharacters: 4_000,
            composerCharacters: 8
        )
        XCTAssertEqual(tokens, 12_400 + 20 + 2)
    }

    func testFractionNilWhenMaxUnknown() {
        XCTAssertNil(ContextUsageEstimator.fraction(used: 10, maxTokens: nil))
        XCTAssertNil(ContextUsageEstimator.fraction(used: 10, maxTokens: 0))
        XCTAssertEqual(ContextUsageEstimator.fraction(used: 50, maxTokens: 200), 0.25)
    }

    func testLevelThresholds() {
        XCTAssertEqual(ContextUsageEstimator.level(for: 0.0), .normal)
        XCTAssertEqual(ContextUsageEstimator.level(for: 0.69), .normal)
        XCTAssertEqual(ContextUsageEstimator.level(for: 0.7), .warning)
        XCTAssertEqual(ContextUsageEstimator.level(for: 0.9), .warning)
        XCTAssertEqual(ContextUsageEstimator.level(for: 0.91), .critical)
        XCTAssertEqual(ContextUsageEstimator.level(for: 1.4), .critical)
    }

    func testTooltipAndFormatting() {
        XCTAssertEqual(ContextUsageEstimator.tooltip(used: 12_400, maxTokens: 200_000), "~12.4k of 200k tokens (6%)")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(950), "950")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(1_000), "1k")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(128_000), "128k")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(999_960), "1M")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(1_048_576), "1M")
        XCTAssertEqual(ContextUsageEstimator.formattedTokenCount(1_500_000), "1.5M")
    }
}
