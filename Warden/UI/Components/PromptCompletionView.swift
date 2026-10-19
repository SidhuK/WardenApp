import CoreData
import SwiftUI

/// Drives the "/" prompt menu for one composer.
///
/// The text editor reports every text change through `update(for:)` and, while `isVisible`, routes
/// arrow keys, Return, Tab and Esc here instead of performing their default actions.
@MainActor
final class PromptCompletionState: ObservableObject {
    @Published private(set) var query: String?
    @Published private var storedSuggestions: [PromptEntity] = []
    @Published var selectedIndex = 0

    static let maxSuggestions = 8

    private let library: PromptLibraryManager
    /// Text at the moment Esc was pressed; the menu stays closed until the text changes.
    private var dismissedText: String?

    init(library: PromptLibraryManager? = nil) {
        self.library = library ?? .shared
    }

    /// Prompts deleted from the library while the menu is open are dropped, since reading them would fault.
    var suggestions: [PromptEntity] {
        storedSuggestions.filter { !$0.isDeleted && $0.managedObjectContext != nil }
    }

    var isVisible: Bool {
        query != nil && !suggestions.isEmpty
    }

    var selectedPrompt: PromptEntity? {
        let suggestions = suggestions
        guard suggestions.indices.contains(selectedIndex) else { return suggestions.first }
        return suggestions[selectedIndex]
    }

    /// The query typed after a leading "/", or nil when the text isn't a slash command in progress.
    /// Only `/` followed by non-whitespace characters qualifies: `"/sum"` → `"sum"`, `"/sum x"` → nil.
    nonisolated static func slashQuery(in text: String) -> String? {
        guard text.hasPrefix("/") else { return nil }
        let query = text.dropFirst()
        guard !query.contains(where: { $0.isWhitespace || $0.isNewline }) else { return nil }
        return String(query)
    }

    func update(for text: String) {
        if let dismissedText, dismissedText != text {
            self.dismissedText = nil
        }

        let newQuery = dismissedText == nil ? Self.slashQuery(in: text) : nil
        guard newQuery != query || (newQuery != nil && suggestions.isEmpty) else { return }

        query = newQuery
        storedSuggestions = newQuery.map { library.prompts(matching: $0, limit: Self.maxSuggestions) } ?? []
        selectedIndex = 0
    }

    func moveSelection(by delta: Int) {
        let suggestions = suggestions
        guard !suggestions.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + suggestions.count) % suggestions.count
    }

    /// Closes the menu without touching the text.
    func dismiss(currentText: String) {
        dismissedText = currentText
        close()
    }

    /// Records the use of `prompt` (or the highlighted one) and returns the text that replaces the `/query`.
    func accept(_ prompt: PromptEntity? = nil) -> String? {
        guard let prompt = prompt ?? selectedPrompt, !prompt.isDeleted, prompt.managedObjectContext != nil else {
            return nil
        }
        let content = prompt.content
        library.recordUse(prompt)
        close()
        // Content that is itself a "/word" would otherwise reopen the menu as soon as it's inserted.
        dismissedText = content
        return content
    }

    private func close() {
        query = nil
        storedSuggestions = []
        selectedIndex = 0
    }
}

/// Floating list of prompt suggestions shown above the composer while a "/" query is active.
struct PromptCompletionListView: View {
    @ObservedObject var state: PromptCompletionState
    var onSelect: (PromptEntity) -> Void
    @Environment(\.wardenTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(state.suggestions.enumerated()), id: \.element.objectID) { index, prompt in
                PromptCompletionRow(prompt: prompt, isHighlighted: index == state.selectedIndex)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        if hovering { state.selectedIndex = index }
                    }
                    .onTapGesture { onSelect(prompt) }
            }

            Text("↑↓ to navigate · Return or Tab to insert · Esc to dismiss")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8)
                .padding(.top, 4)
        }
        .padding(6)
        .frame(maxWidth: 420, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.surfaceBackground)
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(theme.surfaceBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Prompt suggestions")
    }
}

private struct PromptCompletionRow: View {
    @ObservedObject var prompt: PromptEntity
    let isHighlighted: Bool

    private var preview: String {
        prompt.content
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }

    var body: some View {
        if !prompt.isDeleted, prompt.managedObjectContext != nil {
            row
        }
    }

    private var row: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(isHighlighted ? .accentColor : .secondary)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(prompt.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)

                    if let shortcut = prompt.shortcut, !shortcut.isEmpty {
                        Text("/\(shortcut)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}
