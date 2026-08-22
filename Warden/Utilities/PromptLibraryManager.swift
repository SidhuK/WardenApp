import CoreData
import Foundation
import os

/// Manages the user's prompt library: CRUD, usage accounting, and first-run presets.
@MainActor
final class PromptLibraryManager {
    static let shared = PromptLibraryManager()

    private let viewContext: NSManagedObjectContext
    private static let presetsAddedKey = "promptLibraryPresetsAdded"

    init(viewContext: NSManagedObjectContext = PersistenceController.shared.container.viewContext) {
        self.viewContext = viewContext
        addPresetsIfNeeded()
    }

    // MARK: - CRUD

    @discardableResult
    func addPrompt(
        name: String,
        content: String,
        shortcut: String? = nil,
        category: String? = nil
    ) -> PromptEntity {
        let prompt = PromptEntity(context: viewContext)
        prompt.id = UUID()
        prompt.name = name
        prompt.content = content
        prompt.shortcut = normalizedShortcut(shortcut)
        prompt.category = category?.isEmpty == true ? nil : category
        prompt.createdDate = Date()
        save()
        return prompt
    }

    func delete(_ prompt: PromptEntity) {
        viewContext.delete(prompt)
        save()
    }

    func duplicate(_ prompt: PromptEntity) -> PromptEntity {
        let copy = addPrompt(
            name: (prompt.name ?? "Prompt") + " Copy",
            content: prompt.content ?? "",
            shortcut: nil,
            category: prompt.category
        )
        return copy
    }

    /// Bumps usage stats when a prompt is inserted into a message.
    func recordUse(_ prompt: PromptEntity) {
        prompt.usageCount += 1
        prompt.lastUsedDate = Date()
        save()
    }

    /// All prompts matching a slash-command query, e.g. query "exp" matches "/explain".
    /// Sorted by usage count (most used first) so autocomplete ranks favorites.
    func prompts(matchingQuery query: String?) -> [PromptEntity] {
        let request = NSFetchRequest<PromptEntity>(entityName: "PromptEntity")
        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            request.predicate = NSPredicate(
                format: "name CONTAINS[cd] %@ OR shortcut CONTAINS[cd] %@",
                query, query
            )
        }
        request.sortDescriptors = [
            NSSortDescriptor(key: "usageCount", ascending: false),
            NSSortDescriptor(key: "name", ascending: true),
        ]
        request.fetchLimit = 20

        do {
            return try viewContext.fetch(request)
        } catch {
            WardenLog.app.error(
                "[Prompts] Failed to fetch prompts: \(error.localizedDescription, privacy: .public)"
            )
            return []
        }
    }

    func promptCount() -> Int {
        let request = NSFetchRequest<PromptEntity>(entityName: "PromptEntity")
        return (try? viewContext.count(for: request)) ?? 0
    }

    // MARK: - Presets

    struct Preset {
        let name: String
        let shortcut: String
        let content: String
        let category: String
    }

    static let defaultPresets: [Preset] = [
        Preset(
            name: "Explain This",
            shortcut: "explain",
            content: "Explain the following in simple terms. Define any jargon, use an analogy where helpful, and end with the single most important takeaway.\n\n{{text}}",
            category: "General"
        ),
        Preset(
            name: "Summarize",
            shortcut: "summarize",
            content: "Summarize the text below. Provide: 1) A one-sentence TL;DR, 2) Three to five key points as bullets. Keep it under 150 words.\n\n{{text}}",
            category: "Writing"
        ),
        Preset(
            name: "Proofread",
            shortcut: "proofread",
            content: "Proofread the following text. Fix grammar, spelling, and clarity issues without changing my voice or meaning. Return only the corrected text.\n\n{{text}}",
            category: "Writing"
        ),
        Preset(
            name: "Code Review",
            shortcut: "review",
            content: "Review this code for bugs, edge cases, performance issues, and readability. Be specific — point to exact lines and suggest concrete fixes. Do not rewrite working code unnecessarily.\n\n```\n{{text}}\n```",
            category: "Engineering"
        ),
        Preset(
            name: "Translate",
            shortcut: "translate",
            content: "Translate the following into natural, idiomatic English. Preserve tone and formatting. If any term is ambiguous, list alternatives in brackets.\n\n{{text}}",
            category: "General"
        ),
    ]

    private func addPresetsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.presetsAddedKey) else { return }

        for preset in Self.defaultPresets {
            let prompt = PromptEntity(context: viewContext)
            prompt.id = UUID()
            prompt.name = preset.name
            prompt.content = preset.content
            prompt.shortcut = preset.shortcut
            prompt.category = preset.category
            prompt.createdDate = Date()
        }

        do {
            try viewContext.save()
            defaults.set(true, forKey: Self.presetsAddedKey)
            #if DEBUG
            WardenLog.app.debug("[Prompts] Seeded \(Self.defaultPresets.count, privacy: .public) starter prompts")
            #endif
        } catch {
            viewContext.rollback()
            WardenLog.app.error(
                "[Prompts] Failed to seed presets: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // MARK: - Helpers

    private func normalizedShortcut(_ shortcut: String?) -> String? {
        guard var value = shortcut?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !value.isEmpty else { return nil }
        if value.hasPrefix("/") { value.removeFirst() }
        return value
    }

    private func save() {
        guard viewContext.hasChanges else { return }
        do {
            try viewContext.save()
        } catch {
            WardenLog.app.error(
                "[Prompts] Save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
