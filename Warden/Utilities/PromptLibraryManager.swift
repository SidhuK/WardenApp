import CoreData
import Foundation
import os

/// The user's library of reusable prompts: CRUD, slash-command matching, usage accounting and first-run defaults.
@MainActor
final class PromptLibraryManager: ObservableObject {
    static let shared = PromptLibraryManager(context: PersistenceController.shared.container.viewContext)

    struct DefaultPrompt {
        let name: String
        let shortcut: String
        let content: String
    }

    static let defaultPrompts: [DefaultPrompt] = [
        DefaultPrompt(
            name: "Summarize",
            shortcut: "summarize",
            content: """
                Summarize the following. Start with a one-sentence TL;DR, then list the 3-5 most important \
                points as bullets. Keep it under 150 words.

                """
        ),
        DefaultPrompt(
            name: "Translate",
            shortcut: "translate",
            content: """
                Translate the following into natural, idiomatic English. If it is already in English, translate \
                it into the language I name instead. Preserve tone and formatting.

                """
        ),
        DefaultPrompt(
            name: "Fix grammar",
            shortcut: "fix",
            content: """
                Fix the grammar, spelling and punctuation in the following text without changing its meaning \
                or voice. Return only the corrected text.

                """
        ),
        DefaultPrompt(
            name: "Explain",
            shortcut: "explain",
            content: """
                Explain the following in simple terms. Define any jargon, use an analogy where it helps, and \
                end with the single most important takeaway.

                """
        ),
        DefaultPrompt(
            name: "Code review",
            shortcut: "review",
            content: """
                Review this code for bugs, edge cases, performance and readability. Point to specific lines \
                and suggest concrete fixes; don't rewrite code that already works.

                """
        ),
    ]

    static let defaultsSeededKey = "promptLibraryDefaultsSeeded"

    private let context: NSManagedObjectContext
    private let userDefaults: UserDefaults

    init(context: NSManagedObjectContext, userDefaults: UserDefaults = .standard) {
        self.context = context
        self.userDefaults = userDefaults
    }

    // MARK: - Queries

    /// Every prompt, most used first.
    func allPrompts() -> [PromptEntity] {
        fetchAll().sorted(by: Self.usageOrder)
    }

    /// The most used (then most recently used) prompts, e.g. for suggestion cards.
    func topPrompts(limit: Int) -> [PromptEntity] {
        Array(allPrompts().prefix(max(limit, 0)))
    }

    /// Prompts for a slash-command query such as `"sum"` or `"/sum"`.
    ///
    /// Prefix matches on the shortcut rank first, then prefix matches on the name (or any word of it), then
    /// substring matches, then in-order character matches. Within a tier, more used and more recently used
    /// prompts come first. An empty query returns every prompt in usage order.
    func prompts(matching query: String, limit: Int? = nil) -> [PromptEntity] {
        let normalized = Self.normalizedQuery(query)
        let candidates = fetchAll()

        let ranked: [PromptEntity]
        if normalized.isEmpty {
            ranked = candidates.sorted(by: Self.usageOrder)
        } else {
            ranked = candidates
                .compactMap { prompt in Self.matchTier(for: prompt, query: normalized).map { (prompt, $0) } }
                .sorted { lhs, rhs in
                    if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                    return Self.usageOrder(lhs.0, rhs.0)
                }
                .map(\.0)
        }

        if let limit { return Array(ranked.prefix(max(limit, 0))) }
        return ranked
    }

    // MARK: - Mutations

    @discardableResult
    func addPrompt(name: String, content: String, shortcut: String?) -> PromptEntity? {
        guard
            let prompt = NSEntityDescription.insertNewObject(forEntityName: "PromptEntity", into: context)
                as? PromptEntity
        else { return nil }
        prompt.id = UUID()
        prompt.createdDate = Date()
        prompt.usageCount = 0
        apply(name: name, content: content, shortcut: shortcut, to: prompt)
        return save() ? prompt : nil
    }

    func updatePrompt(_ prompt: PromptEntity, name: String, content: String, shortcut: String?) {
        apply(name: name, content: content, shortcut: shortcut, to: prompt)
        save()
    }

    func deletePrompt(_ prompt: PromptEntity) {
        context.delete(prompt)
        save()
    }

    func recordUse(_ prompt: PromptEntity) {
        prompt.usageCount += 1
        prompt.lastUsedDate = Date()
        save()
    }

    /// Adds the starter prompts the first time the library is used on an empty store.
    func seedDefaultsIfNeeded() {
        guard !userDefaults.bool(forKey: Self.defaultsSeededKey) else { return }

        if fetchAll().isEmpty {
            for preset in Self.defaultPrompts {
                guard
                    let prompt = NSEntityDescription.insertNewObject(forEntityName: "PromptEntity", into: context)
                        as? PromptEntity
                else { continue }
                prompt.id = UUID()
                prompt.createdDate = Date()
                prompt.usageCount = 0
                apply(name: preset.name, content: preset.content, shortcut: preset.shortcut, to: prompt)
            }
            guard save() else { return }
        }

        userDefaults.set(true, forKey: Self.defaultsSeededKey)
    }

    // MARK: - Helpers

    /// Shortcuts are stored lowercased, without the leading slash, with whitespace turned into dashes.
    static func normalizedShortcut(_ shortcut: String?) -> String? {
        guard var value = shortcut?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return nil
        }
        while value.hasPrefix("/") { value.removeFirst() }
        value = value.split(whereSeparator: \.isWhitespace).joined(separator: "-")
        return value.isEmpty ? nil : value
    }

    private static func normalizedQuery(_ query: String) -> String {
        var value = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while value.hasPrefix("/") { value.removeFirst() }
        return value
    }

    private static func matchTier(for prompt: PromptEntity, query: String) -> Int? {
        let shortcut = prompt.shortcut?.lowercased() ?? ""
        let name = prompt.name.lowercased()
        let nameWords = name.split(whereSeparator: { !$0.isLetter && !$0.isNumber })

        if shortcut.hasPrefix(query) { return 0 }
        if name.hasPrefix(query) || nameWords.contains(where: { $0.hasPrefix(query) }) { return 1 }
        if shortcut.contains(query) || name.contains(query) { return 2 }
        if query.count >= 2, isSubsequence(query, of: shortcut) || isSubsequence(query, of: name) { return 3 }
        return nil
    }

    private static func isSubsequence(_ needle: String, of haystack: String) -> Bool {
        var remaining = needle[...]
        for character in haystack where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    private static func usageOrder(_ lhs: PromptEntity, _ rhs: PromptEntity) -> Bool {
        if lhs.usageCount != rhs.usageCount { return lhs.usageCount > rhs.usageCount }
        switch (lhs.lastUsedDate, rhs.lastUsedDate) {
        case let (l?, r?) where l != r: return l > r
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }

    private func apply(name: String, content: String, shortcut: String?, to prompt: PromptEntity) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        prompt.name = trimmedName.isEmpty ? "Untitled Prompt" : trimmedName
        prompt.content = content
        prompt.shortcut = Self.normalizedShortcut(shortcut)
    }

    /// Undoes unsaved prompt inserts and edits only. The context is the app's shared view context, so a full
    /// `rollback()` would also discard unrelated unsaved chat edits.
    private func revertPromptChanges() {
        for case let prompt as PromptEntity in context.insertedObjects {
            context.delete(prompt)
        }
        for case let prompt as PromptEntity in context.updatedObjects {
            context.refresh(prompt, mergeChanges: false)
        }
    }

    private func fetchAll() -> [PromptEntity] {
        do {
            return try context.fetch(PromptEntity.fetchRequest())
        } catch {
            WardenLog.coreData.error("Failed to fetch prompts: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    @discardableResult
    private func save() -> Bool {
        objectWillChange.send()
        guard context.hasChanges else { return true }
        do {
            try context.save()
            return true
        } catch {
            revertPromptChanges()
            WardenLog.coreData.error("Failed to save prompts: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
