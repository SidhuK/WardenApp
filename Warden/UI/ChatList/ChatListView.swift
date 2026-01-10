import CoreData
import SwiftUI
import os

struct ChatListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var scrollOffset: CGFloat = 0
    @State private var previousOffset: CGFloat = 0
    @State private var newChatButtonTapped = false
    @State private var settingsButtonTapped = false
    @State private var selectedChatIDs: Set<UUID> = []
    @State private var lastSelectedChatID: UUID?
    @FocusState private var isSearchFocused: Bool
    
    // Search performance optimization
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var searchResults: Set<UUID> = []
    @State private var isSearching = false
    
    @MainActor
    private func presentAlert(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ]
    )
    private var chats: FetchedResults<ChatEntity>

    @Binding var selectedChat: ChatEntity?
    @Binding var selectedProject: ProjectEntity?
    @Binding var showingCreateProject: Bool
    @Binding var showingEditProject: Bool
    @Binding var projectToEdit: ProjectEntity?
    
    let onNewChat: () -> Void
    let onOpenPreferences: () -> Void

    // MARK: - Date Grouping Logic
    
    enum DateGroup: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case older = "Older"
    }
    
    private func dateGroup(for date: Date) -> DateGroup {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return .today
        } else if calendar.isDateInYesterday(date) {
            return .yesterday
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            return .thisWeek
        } else if calendar.isDate(date, equalTo: now, toGranularity: .month) {
            return .thisMonth
        } else {
            return .older
        }
    }
    
    private var groupedChatsWithoutProject: [DateGroup: [ChatEntity]] {
        let chatsToGroup = unpinnedChatsWithoutProject
        var grouped: [DateGroup: [ChatEntity]] = [:]
        
        for chat in chatsToGroup {
            let group = dateGroup(for: chat.updatedDate)
            if grouped[group] == nil {
                grouped[group] = []
            }
            grouped[group]?.append(chat)
        }
        
        return grouped
    }
    
    private var pinnedChatsWithoutProject: [ChatEntity] {
        return chatsWithoutProject.filter { $0.isPinned }
    }
    
    private var unpinnedChatsWithoutProject: [ChatEntity] {
        return chatsWithoutProject.filter { !$0.isPinned }
    }

    private var filteredChats: [ChatEntity] {
        guard !debouncedSearchText.isEmpty else { return Array(chats) }
        
        // Use search results from background task
        return chats.filter { chat in
            searchResults.contains(chat.id)
        }
    }
    
    private var chatsWithoutProject: [ChatEntity] {
        let allChats = debouncedSearchText.isEmpty ? Array(chats) : filteredChats
        return allChats.filter { $0.project == nil }
    }
    
    // MARK: - Background Search
    
    private func performSearch(_ query: String) {
        // Cancel any existing search
        searchTask?.cancel()
        
        guard !query.isEmpty else {
            debouncedSearchText = ""
            searchResults.removeAll()
            isSearching = false
            return
        }
        
        isSearching = true
        
        searchTask = Task(priority: .userInitiated) {
            var matchingChatIDs: Set<UUID> = []

            let backgroundContext = PersistenceController.shared.container.newBackgroundContext()

            await backgroundContext.perform {
                let namePredicate = NSPredicate(format: "name CONTAINS[cd] %@", query)
                let systemMessagePredicate = NSPredicate(format: "systemMessage CONTAINS[cd] %@", query)
                let personaNamePredicate = NSPredicate(format: "persona.name CONTAINS[cd] %@", query)

                let metadataRequest = NSFetchRequest<NSDictionary>(entityName: "ChatEntity")
                metadataRequest.resultType = .dictionaryResultType
                metadataRequest.propertiesToFetch = ["id"]
                metadataRequest.returnsDistinctResults = true
                metadataRequest.predicate = NSCompoundPredicate(orPredicateWithSubpredicates: [
                    namePredicate,
                    systemMessagePredicate,
                    personaNamePredicate
                ])

                let messageRequest = NSFetchRequest<NSDictionary>(entityName: "ChatEntity")
                messageRequest.resultType = .dictionaryResultType
                messageRequest.propertiesToFetch = ["id"]
                messageRequest.returnsDistinctResults = true
                messageRequest.predicate = NSPredicate(format: "ANY messages.body CONTAINS[cd] %@", query)

                do {
                    for dict in try backgroundContext.fetch(metadataRequest) {
                        if Task.isCancelled { return }
                        if let id = dict["id"] as? UUID {
                            matchingChatIDs.insert(id)
                        }
                    }

                    for dict in try backgroundContext.fetch(messageRequest) {
                        if Task.isCancelled { return }
                        if let id = dict["id"] as? UUID {
                            matchingChatIDs.insert(id)
                        }
                    }
                } catch {
                    WardenLog.app.error("Search error: \(error.localizedDescription, privacy: .public)")
                }
            }

            if Task.isCancelled { return }
            await MainActor.run {
                self.searchResults = matchingChatIDs
                self.debouncedSearchText = query
                self.isSearching = false
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // New Chat button at the top
            newChatButtonSection
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // Search bar
            searchBarSection
                .padding(.bottom, 8)

            // Selection toolbar (only shown when chats are selected)
            if !selectedChatIDs.isEmpty {
                selectionToolbar
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }

            List(selection: $selectedChatIDs) {
                // Projects section
                projectsSection
                
                // Chats without project section
                if !chatsWithoutProject.isEmpty {
                    chatsWithoutProjectSection
                }
            }
            .listStyle(.sidebar)
            .onDeleteCommand {
                deleteSelectedChats()
            }
            .onExitCommand {
                selectedChatIDs.removeAll()
                lastSelectedChatID = nil
            }
            
            // Settings button at the bottom
            bottomSettingsSection
                .padding(.bottom, 12)
        }
        .onChange(of: selectedChat) { _, newValue in
            guard let newValue else { return }
            guard !selectedChatIDs.contains(newValue.id) else { return }
            selectedChatIDs = [newValue.id]
            lastSelectedChatID = newValue.id
        }
        .onChange(of: selectedProject) { _, newValue in
            guard newValue != nil else { return }
            selectedChatIDs.removeAll()
            lastSelectedChatID = nil
        }
        .onChange(of: selectedChatIDs) { oldValue, newValue in
            let added = newValue.subtracting(oldValue)
            if let lastAdded = added.first {
                lastSelectedChatID = lastAdded
            }

            guard let activeID = lastSelectedChatID ?? newValue.first else {
                selectedChat = nil
                return
            }

            if selectedChat?.id != activeID, let chat = chats.first(where: { $0.id == activeID }) {
                selectedChat = chat
            }
        }
        .onChange(of: selectedChat) { _, _ in
            isSearchFocused = false
        }
        .onReceive(NotificationCenter.default.publisher(for: AppConstants.newChatHotkeyNotification)) { _ in
            onNewChat()
        }
    }

    private var newChatButtonSection: some View {
        VStack(spacing: 0) {
            newChatButton
        }
        .padding(.horizontal)
    }

    private var searchBarSection: some View {
        HStack {
            // Show loading indicator or magnifying glass
            if isSearching {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
            }

            TextField("Search chats...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body))
                .focused($isSearchFocused)
                .accessibilityLabel("Search chats")
                .onExitCommand {
                    searchText = ""
                    isSearchFocused = false
                }
                .onChange(of: searchText) { oldValue, newValue in
                    // Debounce search by 300ms
                    searchTask?.cancel()
                    
                    if newValue.isEmpty {
                        debouncedSearchText = ""
                        searchResults.removeAll()
                        isSearching = false
                    } else {
                        isSearching = true
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
                            if !Task.isCancelled {
                                performSearch(newValue)
                            }
                        }
                    }
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                    debouncedSearchText = ""
                    searchResults.removeAll()
                    isSearching = false
                    searchTask?.cancel()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(8)
        .background(
            Group {
                if isSearchFocused {
                    Color(NSColor.controlBackgroundColor).opacity(0.6)
                } else {
                    // Light mode: slightly darker background, Dark mode: slightly lighter background
                    Color.primary.opacity(0.05)
                }
            }
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .padding(.horizontal)
    }

    private var bottomSettingsSection: some View {
        VStack(spacing: 0) {
            settingsButton
        }
        .padding(.horizontal)
    }

    private var newChatButton: some View {
        Button(action: {
            newChatButtonTapped.toggle()
            onNewChat()
        }) {
            ZStack {
                // Icon on the left
                HStack {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14, weight: .medium))
                        .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: newChatButtonTapped)
                    Spacer()
                }
                .padding(.horizontal, 12)

                // Text centered
                Text("New Thread")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .accessibilityLabel("New Thread")
    }
    
    private var settingsButton: some View {
        // Simplified settings button at bottom with text and icon, smaller size
        Button(action: {
            settingsButtonTapped.toggle()
            onOpenPreferences()
        }) {
            HStack(spacing: 6) {
                Image(systemName: "gear")
                    .font(.system(size: 12, weight: .medium))
                Text("Settings")
                    .font(.system(size: 12, weight: .medium))
            }
            .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: settingsButtonTapped)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var selectionToolbar: some View {
        HStack(spacing: 8) {
            Text("\(selectedChatIDs.count) selected")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Button {
                if selectedChatIDs.count == filteredChats.count {
                    selectedChatIDs.removeAll()
                    lastSelectedChatID = nil
                } else {
                    selectedChatIDs = Set(filteredChats.map { $0.id })
                    lastSelectedChatID = filteredChats.last?.id
                }
            } label: {
                Text(selectedChatIDs.count == filteredChats.count ? "Deselect All" : "Select All")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            
            Button(role: .destructive) {
                deleteSelectedChats()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
            }
            .buttonStyle(.borderless)
            .disabled(selectedChatIDs.isEmpty)
            .accessibilityLabel("Delete selected chats")
            
            Button {
                selectedChatIDs.removeAll()
                lastSelectedChatID = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Clear selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func deleteSelectedChats() {
        guard !selectedChatIDs.isEmpty else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete \(selectedChatIDs.count) chat\(selectedChatIDs.count == 1 ? "" : "s")?"
        alert.informativeText = "Are you sure you want to delete the selected chats? This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        presentAlert(alert) { response in
            if response == .alertFirstButtonReturn {
                // Clear selectedChat if it's in the list to be deleted
                if let selectedChatID = selectedChat?.id, selectedChatIDs.contains(selectedChatID) {
                    selectedChat = nil
                }
                
                // Perform bulk delete
                store.deleteSelectedChats(selectedChatIDs)
                
                // Clear selection
                selectedChatIDs.removeAll()
                lastSelectedChatID = nil
            }
        }
    }

    // MARK: - Section Views
    
    private var projectsSection: some View {
        Group {
            // Active projects - each as individual list item
            ForEach(store.getActiveProjects(), id: \.id) { project in
                ProjectRowInList(
                    project: project,
                    selectedProject: $selectedProject,
                    searchText: $searchText,
                    showingCreateProject: $showingCreateProject,
                    showingEditProject: $showingEditProject,
                    projectToEdit: $projectToEdit,
                    onNewChatInProject: { project in
                        let newChat = store.createChat(in: project)
                        selectedChat = newChat
                    }
                )
            }
            
            // Archived projects section (if any exist and are shown)
            if !getArchivedProjects().isEmpty {
                archivedProjectsSection
            }
        }
    }
    
    @State private var showingArchivedProjects = false
    
    private func getArchivedProjects() -> [ProjectEntity] {
        return store.getProjectsPaginated(limit: 100, offset: 0, includeArchived: true)
            .filter { $0.isArchived }
    }
    
    private var archivedProjectsSection: some View {
        Group {
            // Archived projects header
            Section {
                EmptyView()
            } header: {
                Button(action: {
                    showingArchivedProjects.toggle()
                }) {
                    HStack {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .rotationEffect(.degrees(showingArchivedProjects ? 90 : 0))
                            .animation(.easeInOut(duration: 0.2), value: showingArchivedProjects)
                        
                        Text("Archived Projects")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Text("(\(getArchivedProjects().count))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            // Archived projects list
            if showingArchivedProjects {
                ForEach(getArchivedProjects(), id: \.id) { project in
                    ProjectRowInList(
                        project: project,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
                        showingCreateProject: $showingCreateProject,
                        showingEditProject: $showingEditProject,
                        projectToEdit: $projectToEdit,
                        onNewChatInProject: { project in
                            // Unarchive if adding a new chat? Or allow adding to archived?
                            // Current behavior allows it, so we keep allowing it.
                            let newChat = store.createChat(in: project)
                            selectedChat = newChat
                        },
                        isArchived: true
                    )
                }
            }
        }
    }
    
    private var chatsWithoutProjectSection: some View {
        Group {
            // Show pinned chats first (at the very top, before any date groups)
            if !pinnedChatsWithoutProject.isEmpty {
                Section {
                    ForEach(pinnedChatsWithoutProject, id: \.id) { chat in
                        ChatListRow(
                            chat: chat,
                            selectedChat: $selectedChat,
                            viewContext: viewContext,
                            searchText: searchText,
                            isSelectionMode: selectedChatIDs.count > 1,
                            isSelected: selectedChatIDs.contains(chat.id),
                            onSelectionToggle: { chatID, isSelected in
                                if isSelected {
                                    selectedChatIDs.insert(chatID)
                                } else {
                                    selectedChatIDs.remove(chatID)
                                }
                            }
                        )
                        .tag(chat.id)
                    }
                } header: {
                    HStack {
                        Text("Pinned")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
                }
            }
            
            // Show date-grouped unpinned chats
            ForEach(DateGroup.allCases, id: \.self) { dateGroup in
                if let chatsInGroup = groupedChatsWithoutProject[dateGroup], !chatsInGroup.isEmpty {
                    Section {
                        ForEach(chatsInGroup, id: \.id) { chat in
                            ChatListRow(
                                chat: chat,
                                selectedChat: $selectedChat,
                                viewContext: viewContext,
                                searchText: searchText,
                                isSelectionMode: selectedChatIDs.count > 1,
                                isSelected: selectedChatIDs.contains(chat.id),
                                onSelectionToggle: { chatID, isSelected in
                                    if isSelected {
                                        selectedChatIDs.insert(chatID)
                                    } else {
                                        selectedChatIDs.remove(chatID)
                                    }
                                }
                            )
                            .tag(chat.id)
                        }
                    } header: {
                        HStack {
                            Text(dateGroup.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}
