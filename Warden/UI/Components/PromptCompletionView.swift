import CoreData
import SwiftUI

/// Drives the "/" prompt-completion experience for one composer.
///
/// Owns the active query (text after the leading "/") and the highlighted row.
/// The text editor consults `isVisible` to divert Enter/arrows/Esc; the composer
/// renders `PromptCompletionListView` while visible.
@MainActor
final class PromptCompletionState: ObservableObject {
    /// Text typed after the "/" trigger. nil = completion not active.
    @Published var query: String? {
        didSet { selectedIndex = 0 }
    }
    @Published var selectedIndex: Int = 0

    private let library: PromptLibraryManager

    init(library: PromptLibraryManager = .shared) {
        self.library = library
    }

    /// Visible only while there is an active query AND at least one suggestion,
    /// otherwise arrow keys would be consumed with nothing to navigate.
    var isVisible: Bool {
        guard query != nil else { return false }
        return !suggestions.isEmpty
    }

    var suggestions: [PromptEntity] {
        library.prompts(matchingQuery: query)
    }

    var selectedPrompt: PromptEntity? {
        let items = suggestions
        guard !items.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), items.count - 1)
        return items[index]
    }

    /// Parses composer text into an active query: a line that is exactly "/..." .
    static func activeQuery(in text: String) -> String? {
        guard let lastLine = text.split(separator: "\n", omittingEmptySubsequences: false).last else {
            return nil
        }
        guard lastLine.hasPrefix("/"), lastLine.count >= 1 else { return nil }
        let query = String(lastLine.dropFirst())
        // A space after the command ends completion — the user moved on.
        guard !query.contains(" ") else { return nil }
        return query
    }

    func sync(with text: String) {
        let parsed = Self.activeQuery(in: text)
        if parsed != query {
            query = parsed
        }
    }

    func dismiss() {
        query = nil
    }

    func moveSelection(_ delta: Int) {
        let count = suggestions.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + delta + count) % count
    }

    /// Applies the chosen (or top) prompt to the composer text.
    /// Pass `prompt` explicitly from tap/activation paths; keyboard acceptance
    /// omits it and uses the currently highlighted row.
    /// Returns the replacement text, or nil if nothing could be applied.
    @discardableResult
    func acceptSelected(
        currentText: String,
        libraryManager: PromptLibraryManager,
        prompt: PromptEntity? = nil
    ) -> String? {
        guard let prompt = prompt ?? selectedPrompt,
              let content = prompt.resolvedContent(selection: nil) else {
            return nil
        }

        libraryManager.recordUse(prompt)

        // Replace the trailing "/query" line with the resolved content.
        var lines = currentText.split(separator: "\n", omittingEmptySubsequences: false)
        if let lastLineIndex = lines.indices.last, lines[lastLineIndex].hasPrefix("/") {
            lines[lastLineIndex] = Substring(content)
        } else {
            lines.append(Substring(content))
        }
        let newText = lines.joined(separator: "\n")
        dismiss()
        return newText
    }
}

/// Floating suggestion list shown above the composer while a "/" query is active.
struct PromptCompletionListView: View {
    @ObservedObject var state: PromptCompletionState
    var onSelect: (PromptEntity) -> Void
    @Environment(\.wardenTheme) private var theme

    var body: some View {
        let items = state.suggestions
        Group {
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.objectID) { index, prompt in
                        PromptCompletionRow(
                            prompt: prompt,
                            isHighlighted: index == state.selectedIndex
                        )
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            if hovering { state.selectedIndex = index }
                        }
                        .onTapGesture { onSelect(prompt) }
                    }
                }
                .padding(6)
                .frame(width: 380)
                .background(theme.surfaceBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(theme.surfaceBorder, lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
            }
        }
    }
}

private struct PromptCompletionRow: View {
    let prompt: PromptEntity
    let isHighlighted: Bool
    @Environment(\.wardenTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(isHighlighted ? .accentColor : .secondary)

            Text(prompt.commandTrigger)
                .font(.system(size: 12, weight: .medium, design: .monospaced))

            Text(prompt.name ?? "")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 8)

            if let category = prompt.category, !category.isEmpty {
                Text(category)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(Color.primary.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }
}
