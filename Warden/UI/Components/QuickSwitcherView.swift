import CoreData
import SwiftUI

enum QuickSwitcherMode: Equatable {
    case all
    case models
    case projects
}

enum QuickSwitcherCommand {
    case openChat(ChatEntity)
    case openProject(ProjectEntity)
    case newChat
    case newTemporaryChat
    case selectModel(provider: String, modelId: String)
    case moveChat(to: ProjectEntity?)
    case openSettings
}

/// ⌘K palette: fuzzy search over chats, projects and actions, plus sub-lists for switching the model and moving
/// the current chat to a project. Fully keyboard driven (↑/↓, Return, Esc).
struct QuickSwitcherView: View {
    let chats: [ChatEntity]
    let projects: [ProjectEntity]
    let apiServices: [APIServiceEntity]
    let currentChat: ChatEntity?
    let onCommand: (QuickSwitcherCommand) -> Void
    let onDismiss: () -> Void

    private let initialMode: QuickSwitcherMode
    @State private var mode: QuickSwitcherMode
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isSearchFocused: Bool
    @ObservedObject private var modelCache = ModelCacheManager.shared

    private static let emptyQueryChatLimit = 8
    private static let queryChatLimit = 30
    private static let projectLimit = 8

    init(
        mode: QuickSwitcherMode,
        chats: [ChatEntity],
        projects: [ProjectEntity],
        apiServices: [APIServiceEntity],
        currentChat: ChatEntity?,
        onCommand: @escaping (QuickSwitcherCommand) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.initialMode = mode
        self._mode = State(initialValue: mode)
        self.chats = chats
        self.projects = projects
        self.apiServices = apiServices
        self.currentChat = currentChat
        self.onCommand = onCommand
        self.onDismiss = onDismiss
    }

    var body: some View {
        let sections = self.sections
        let items = sections.flatMap(\.items)

        VStack(spacing: 0) {
            searchField(items: items)
            Divider()
            resultList(sections: sections, items: items)
            Divider()
            footer
        }
        .frame(width: 580)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 12)
        .onAppear {
            isSearchFocused = true
            if mode == .models, !apiServices.isEmpty {
                modelCache.fetchAllModels(from: apiServices)
            }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: mode) { _, newMode in
            query = ""
            selection = 0
            if newMode == .models, !apiServices.isEmpty {
                modelCache.fetchAllModels(from: apiServices)
            }
        }
    }

    // MARK: - Subviews

    private func searchField(items: [Item]) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mode == .models ? "cpu" : (mode == .projects ? "folder" : "magnifyingglass"))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            TextField(placeholder, text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 17))
                .focused($isSearchFocused)
                .onSubmit { perform(items.indices.contains(selection) ? items[selection] : nil) }
                .onKeyPress(.upArrow) {
                    moveSelection(by: -1, count: items.count)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    moveSelection(by: 1, count: items.count)
                    return .handled
                }
                .onKeyPress(.escape) {
                    handleEscape()
                    return .handled
                }
                .accessibilityLabel("Search")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func resultList(sections: [ResultSection], items: [Item]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if items.isEmpty {
                    Text(emptyMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(sections) { section in
                            Text(section.title.uppercased())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 10)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                            ForEach(section.items) { item in
                                let index = items.firstIndex(where: { $0.id == item.id }) ?? 0
                                row(item, isSelected: index == selection)
                                    .id(item.id)
                                    .onTapGesture {
                                        selection = index
                                        perform(item)
                                    }
                            }
                        }
                    }
                    .padding(6)
                }
            }
            .frame(height: 360)
            .onChange(of: selection) { _, newValue in
                guard items.indices.contains(newValue) else { return }
                proxy.scrollTo(items[newValue].id)
            }
        }
    }

    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle = item.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if item.isCurrent {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↑↓", "Navigate")
            hint("↩", "Open")
            hint("esc", mode == initialMode ? "Close" : "Back")
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            Text(label)
        }
    }

    private var placeholder: String {
        switch mode {
        case .all: return "Search chats, projects and actions"
        case .models: return "Switch model…"
        case .projects: return "Move chat to project…"
        }
    }

    private var emptyMessage: String {
        switch mode {
        case .models where orderedProviderTypes.contains(where: { modelCache.isLoading(for: $0) }):
            return "Loading models…"
        case .models:
            return query.isEmpty ? "No models available. Add a provider in Settings." : "No matching models"
        case .projects:
            return query.isEmpty ? "No projects yet" : "No matching projects"
        case .all:
            return "No results"
        }
    }

    // MARK: - Actions

    private func moveSelection(by offset: Int, count: Int) {
        guard count > 0 else { return }
        selection = min(max(selection + offset, 0), count - 1)
    }

    private func handleEscape() {
        if mode != initialMode {
            mode = initialMode
        } else {
            onDismiss()
        }
    }

    private func perform(_ item: Item?) {
        guard let item else { return }
        switch item.action {
        case .command(let command):
            onCommand(command)
        case .switchMode(let newMode):
            mode = newMode
        }
    }

    // MARK: - Results

    private var sections: [ResultSection] {
        switch mode {
        case .all: return allSections
        case .models: return modelSections
        case .projects: return projectSections
        }
    }

    private var actionItems: [Item] {
        var items: [Item] = [
            Item(id: "action.newChat", title: "New Chat", icon: "square.and.pencil", shortcut: "⌘N",
                 action: .command(.newChat)),
            Item(id: "action.newTemporaryChat", title: "New Temporary Chat", subtitle: "Not saved to history",
                 icon: "eye.slash", shortcut: "⇧⌘T", action: .command(.newTemporaryChat)),
            Item(id: "action.switchModel", title: "Switch Model…", icon: "cpu", shortcut: "⌘L",
                 action: .switchMode(.models)),
        ]
        if let currentChat, !currentChat.isTemporary {
            items.append(
                Item(id: "action.moveChat", title: "Move Chat to Project…", icon: "folder", action: .switchMode(.projects))
            )
        }
        items.append(
            Item(id: "action.settings", title: "Open Settings", icon: "gearshape", shortcut: "⌘,",
                 action: .command(.openSettings))
        )
        return items
    }

    private var allSections: [ResultSection] {
        let liveChats = chats.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        let liveProjects = projects.filter { !$0.isDeleted && $0.managedObjectContext != nil }

        let chatItems = liveChats.map { chat -> Item in
            Item(
                id: "chat.\(chat.objectID.uriRepresentation().absoluteString)",
                title: chatTitle(chat),
                subtitle: chat.project?.name,
                icon: chat.isPinned ? "pin" : "bubble.left",
                isCurrent: chat == currentChat,
                action: .command(.openChat(chat))
            )
        }
        let projectItems = liveProjects.map { project -> Item in
            Item(
                id: "project.\(project.objectID.uriRepresentation().absoluteString)",
                title: projectTitle(project),
                subtitle: project.isArchived ? "Archived" : nil,
                icon: "folder",
                action: .command(.openProject(project))
            )
        }

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return [
                ResultSection(id: "actions", title: "Actions", items: actionItems),
                ResultSection(id: "chats", title: "Recent Chats", items: Array(chatItems.prefix(Self.emptyQueryChatLimit))),
                ResultSection(id: "projects", title: "Projects", items: Array(projectItems.prefix(Self.projectLimit))),
            ]
            .filter { !$0.items.isEmpty }
        }

        let rankedChats = rank(chatItems, limit: Self.queryChatLimit)
        let rankedProjects = rank(projectItems, limit: Self.projectLimit)
        let rankedActions = rank(actionItems, limit: actionItems.count)
        // Put whichever group has the best match first so Return picks the most likely result.
        return [
            ResultSection(id: "chats", title: "Chats", items: rankedChats.map(\.item), bestScore: rankedChats.first?.score),
            ResultSection(
                id: "projects", title: "Projects", items: rankedProjects.map(\.item), bestScore: rankedProjects.first?.score
            ),
            ResultSection(
                id: "actions", title: "Actions", items: rankedActions.map(\.item), bestScore: rankedActions.first?.score
            ),
        ]
        .filter { !$0.items.isEmpty }
        .sorted { ($0.bestScore ?? .min) > ($1.bestScore ?? .min) }
    }

    private var modelSections: [ResultSection] {
        let configuredTypes = Set(apiServices.compactMap(\.type))
        let currentProvider = currentChat?.apiService?.type
        let currentModel = currentChat?.gptModel

        var seen = Set<String>()
        func item(provider: String, model: String) -> Item? {
            guard configuredTypes.contains(provider) else { return nil }
            let id = "model.\(provider).\(model)"
            guard seen.insert(id).inserted else { return nil }
            let displayName = ModelMetadata.formatModelComponents(modelId: model, provider: provider).displayName
            return Item(
                id: id,
                title: displayName,
                subtitle: "\(providerName(provider)) · \(model)",
                icon: "cpu",
                isCurrent: provider == currentProvider && model == currentModel,
                searchText: "\(displayName) \(model) \(providerName(provider))",
                action: .command(.selectModel(provider: provider, modelId: model))
            )
        }

        let favorites = FavoriteModelsManager.shared.getAllFavorites()
            .sorted { ($0.provider, $0.model) < ($1.provider, $1.model) }
            .compactMap { item(provider: $0.provider, model: $0.model) }
        let recent = RecentModelsStore.all().compactMap { item(provider: $0.provider, model: $0.model) }
        let all = orderedProviderTypes.flatMap { provider in
            visibleModelIDs(for: provider).compactMap { item(provider: provider, model: $0) }
        }

        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return [
                ResultSection(id: "favorites", title: "Favorites", items: favorites),
                ResultSection(id: "recent", title: "Recent", items: recent),
                ResultSection(id: "models", title: "All Models", items: all),
            ]
            .filter { !$0.items.isEmpty }
        }
        let ranked = rank(favorites + recent + all, limit: 60).map(\.item)
        return ranked.isEmpty ? [] : [ResultSection(id: "models", title: "Models", items: ranked)]
    }

    private var projectSections: [ResultSection] {
        var items: [Item] = []
        if currentChat?.project != nil {
            items.append(
                Item(id: "move.none", title: "No Project", subtitle: "Remove from its project", icon: "folder.badge.minus",
                     action: .command(.moveChat(to: nil)))
            )
        }
        items += projects
            .filter { !$0.isDeleted && $0.managedObjectContext != nil && !$0.isArchived }
            .map { project in
                Item(
                    id: "move.\(project.objectID.uriRepresentation().absoluteString)",
                    title: projectTitle(project),
                    icon: "folder",
                    isCurrent: currentChat?.project == project,
                    action: .command(.moveChat(to: project))
                )
            }
        let visible = query.trimmingCharacters(in: .whitespaces).isEmpty ? items : rank(items, limit: 30).map(\.item)
        return visible.isEmpty ? [] : [ResultSection(id: "projects", title: "Move to Project", items: visible)]
    }

    private func rank(_ items: [Item], limit: Int) -> [(item: Item, score: Int)] {
        let scored: [(item: Item, score: Int)] = items.compactMap { item in
            FuzzyMatcher.score(query, in: item.searchText).map { (item: item, score: $0) }
        }
        return Array(scored.sorted { $0.score > $1.score }.prefix(limit))
    }

    private var orderedProviderTypes: [String] {
        let configured = Set(apiServices.compactMap(\.type))
        let known = AppConstants.apiTypes.filter { configured.contains($0) }
        return known + configured.subtracting(known).sorted()
    }

    private func visibleModelIDs(for provider: String) -> [String] {
        let models = modelCache.getModels(for: provider).map(\.id)
        let selectedModels = SelectedModelsManager.shared
        guard selectedModels.hasCustomSelection(for: provider) else { return models }
        let selected = selectedModels.getSelectedModelIds(for: provider)
        return models.filter { selected.contains($0) }
    }

    private func providerName(_ provider: String) -> String {
        AppConstants.defaultApiConfigurations[provider]?.name ?? provider.capitalized
    }

    private func chatTitle(_ chat: ChatEntity) -> String {
        let name = chat.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Untitled Chat" : name
    }

    private func projectTitle(_ project: ProjectEntity) -> String {
        let name = project.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Untitled Project" : name
    }
}

private struct ResultSection: Identifiable {
    let id: String
    let title: String
    let items: [QuickSwitcherView.Item]
    var bestScore: Int?
}

extension QuickSwitcherView {
    fileprivate struct Item: Identifiable {
        enum Action {
            case command(QuickSwitcherCommand)
            case switchMode(QuickSwitcherMode)
        }

        let id: String
        let title: String
        var subtitle: String?
        let icon: String
        var shortcut: String?
        var isCurrent = false
        var searchText: String
        let action: Action

        init(
            id: String,
            title: String,
            subtitle: String? = nil,
            icon: String,
            shortcut: String? = nil,
            isCurrent: Bool = false,
            searchText: String? = nil,
            action: Action
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.shortcut = shortcut
            self.isCurrent = isCurrent
            self.searchText = searchText ?? title
            self.action = action
        }
    }
}
