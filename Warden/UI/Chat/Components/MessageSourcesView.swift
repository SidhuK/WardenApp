import SwiftUI

/// Numbered source chips shown under an assistant reply that used web search.
/// Chip numbers match inline citations: `[n]` refers to `metadata.sources[n - 1]`.
struct MessageSourcesView: View {
    let metadata: MessageSearchMetadata
    /// Stable identifier of the owning message, used to remember the expanded state across launches.
    let persistenceID: String?

    @State private var isExpanded: Bool

    private static let collapsedLimit = 3

    init(metadata: MessageSearchMetadata, persistenceID: String? = nil) {
        self.metadata = metadata
        self.persistenceID = persistenceID
        _isExpanded = State(initialValue: persistenceID.map(MessageSourcesExpansionStore.isExpanded) ?? false)
    }

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(visibleSources.enumerated()), id: \.offset) { index, source in
                SourceChipView(number: index + 1, source: source)
            }

            if hiddenCount > 0 {
                SourceToggleChip(title: "+\(hiddenCount)", help: "Show all \(metadata.sources.count) sources") {
                    setExpanded(true)
                }
            } else if isExpanded && canCollapse {
                SourceToggleChip(systemImage: "chevron.up", help: "Show fewer sources") {
                    setExpanded(false)
                }
            }
        }
        .padding(.top, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metadata.sources.count) web sources")
        .onChange(of: persistenceID) { _, newID in
            // Core Data swaps a temporary object ID for a permanent one on save.
            if isExpanded, let newID {
                MessageSourcesExpansionStore.setExpanded(true, for: newID)
            }
        }
    }

    /// Avoids a lone "+1" chip by showing every source when only one would be hidden.
    private var canCollapse: Bool {
        metadata.sources.count > Self.collapsedLimit + 1
    }

    private var visibleSources: ArraySlice<SearchSource> {
        if isExpanded || !canCollapse {
            return metadata.sources[...]
        }
        return metadata.sources.prefix(Self.collapsedLimit)
    }

    private var hiddenCount: Int {
        metadata.sources.count - visibleSources.count
    }

    private func setExpanded(_ expanded: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isExpanded = expanded
        }
        if let persistenceID {
            MessageSourcesExpansionStore.setExpanded(expanded, for: persistenceID)
        }
    }
}

// MARK: - Chips

private struct SourceChipView: View {
    let number: Int
    let source: SearchSource

    @State private var isHovered = false
    @State private var showsCard = false
    @State private var hoverTask: Task<Void, Never>?

    private static let hoverCardDelay: Duration = .milliseconds(450)

    var body: some View {
        Button(action: openURL) {
            HStack(spacing: 5) {
                Text("\(number)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.accentColor))

                Text(SourceHoverCard.domain(for: source.url))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isHovered ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 160, alignment: .leading)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .padding(.vertical, 3)
            .background(SourceChipBackground(isHovered: isHovered))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .onHover(perform: handleHover)
        .onDisappear { hoverTask?.cancel() }
        .popover(isPresented: $showsCard, arrowEdge: .bottom) {
            SourceHoverCard(number: number, source: source)
                .contentShape(Rectangle())
                .onTapGesture(perform: openURL)
        }
        .accessibilityLabel("Source \(number), \(SourceHoverCard.domain(for: source.url))")
        .accessibilityHint(source.title)
    }

    private func handleHover(_ hovering: Bool) {
        withAnimation(.easeInOut(duration: 0.12)) {
            isHovered = hovering
        }
        hoverTask?.cancel()
        guard hovering else {
            showsCard = false
            return
        }
        hoverTask = Task { @MainActor in
            try? await Task.sleep(for: Self.hoverCardDelay)
            guard !Task.isCancelled else { return }
            showsCard = true
        }
    }

    private func openURL() {
        hoverTask?.cancel()
        showsCard = false
        if let url = URL(string: source.url) {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct SourceToggleChip: View {
    var title: String? = nil
    var systemImage: String? = nil
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 9, weight: .semibold))
                } else if let title {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .foregroundColor(isHovered ? .primary : .secondary)
            .frame(minHeight: 14)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SourceChipBackground(isHovered: isHovered))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .cursor(.pointingHand)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
        // Clicking swaps this chip out while it's hovered, so the cursor push is never popped by onHover.
        .onDisappear {
            if isHovered { NSCursor.pop() }
        }
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct SourceChipBackground: View {
    let isHovered: Bool

    var body: some View {
        Capsule()
            .fill(Color.primary.opacity(isHovered ? 0.1 : 0.05))
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(isHovered ? 0.14 : 0.08), lineWidth: 0.5)
            )
    }
}

// MARK: - Expanded State Persistence

/// Remembers which messages have their source list expanded. Collapsed is the default, so only
/// expanded IDs are stored, newest last, and the list is capped to keep UserDefaults small.
private enum MessageSourcesExpansionStore {
    private static let defaultsKey = "messageSourcesExpandedIDs"
    private static let maxEntries = 200

    static func isExpanded(_ id: String) -> Bool {
        storedIDs.contains(id)
    }

    static func setExpanded(_ expanded: Bool, for id: String) {
        var ids = storedIDs
        ids.removeAll { $0 == id }
        if expanded {
            ids.append(id)
            if ids.count > maxEntries {
                ids.removeFirst(ids.count - maxEntries)
            }
        }
        UserDefaults.standard.set(ids, forKey: defaultsKey)
    }

    private static var storedIDs: [String] {
        UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
    }
}

// MARK: - Flow Layout

/// Left-aligned layout that wraps subviews onto new lines when the proposed width runs out.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews: subviews, maxWidth: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposedWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if proposedWidth > maxWidth, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty {
            rows.append(current)
        }
        return rows
    }
}

#Preview {
    MessageSourcesView(
        metadata: MessageSearchMetadata(
            query: "latest AI trends 2024",
            sources: [
                SearchSource(
                    title: "OpenAI Announces GPT-4 with Enhanced Capabilities",
                    url: "https://www.techcrunch.com/2024/openai-gpt4",
                    score: 0.95,
                    publishedDate: "2024-01-15"
                ),
                SearchSource(
                    title: "The Future of AI: Trends and Predictions for 2024",
                    url: "https://www.example.com/ai-future",
                    score: 0.82,
                    publishedDate: nil
                ),
                SearchSource(
                    title: "Machine Learning Research Paper on Transformers",
                    url: "https://arxiv.org/abs/2024.12345",
                    score: 0.78,
                    publishedDate: "2024-02-01"
                ),
                SearchSource(
                    title: "AI in Healthcare: Revolutionary Changes",
                    url: "https://healthcare.ai/trends",
                    score: 0.75,
                    publishedDate: "2024-01-20"
                ),
                SearchSource(
                    title: "Deep Learning Advances in Computer Vision",
                    url: "https://cv-research.org/2024",
                    score: 0.70,
                    publishedDate: "2024-02-05"
                ),
            ],
            searchTime: Date(),
            resultCount: 5
        )
    )
    .frame(width: 260)
    .padding()
}
