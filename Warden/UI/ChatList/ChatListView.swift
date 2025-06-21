import CoreData
import SwiftUI

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

    @FetchRequest(
        entity: ChatEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ChatEntity.isPinned, ascending: false),
            NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)
        ],
        animation: .default
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
        let chatsToGroup = chatsWithoutProject
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

    private var filteredChats: [ChatEntity] {
        guard !searchText.isEmpty else { return Array(chats) }

        let searchQuery = searchText.lowercased()
        return chats.filter { chat in
            let name = chat.name.lowercased()
            if name.contains(searchQuery) {
                return true
            }

            if chat.systemMessage.lowercased().contains(searchQuery) {
                return true
            }

            if let personaName = chat.persona?.name?.lowercased(),
                personaName.contains(searchQuery)
            {
                return true
            }

            if let messages = chat.messages.array as? [MessageEntity],
                messages.contains(where: { $0.body.lowercased().contains(searchQuery) })
            {
                return true
            }

            return false
        }
    }
    
    private var chatsWithoutProject: [ChatEntity] {
        let allChats = searchText.isEmpty ? Array(chats) : filteredChats
        return allChats.filter { $0.project == nil }
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

            List {
                // Projects section
                projectsSection
                
                // Chats without project section
                if !chatsWithoutProject.isEmpty {
                    chatsWithoutProjectSection
                }
            }
            .listStyle(.sidebar)
            
            // Settings button at the bottom
            bottomSettingsSection
                .padding(.bottom, 12)
        }
        .background(
            Button("") {
                isSearchFocused = true
            }
            .keyboardShortcut("f", modifiers: .command)
            .opacity(0)
        )
        .background(
            Button("") {
                if !selectedChatIDs.isEmpty {
                    deleteSelectedChats()
                }
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .opacity(0)
        )
        .background(
            Button("") {
                selectedChatIDs.removeAll()
                lastSelectedChatID = nil
            }
            .keyboardShortcut(.escape)
            .opacity(0)
        )
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
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search chats...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
                .font(.system(.body))
                .focused($isSearchFocused)
                .onExitCommand {
                    searchText = ""
                    isSearchFocused = false
                }

            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
                .buttonStyle(PlainButtonStyle())
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

    private var topBarSection: some View {
        HStack(spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)

                TextField("Search chats...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(.body))
                    .focused($isSearchFocused)
                    .onExitCommand {
                        searchText = ""
                        isSearchFocused = false
                    }

                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                    .buttonStyle(PlainButtonStyle())
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
            
            // New chat button
            newChatButton
            
            // Settings button
            settingsButton
        }
        .padding(.horizontal)
    }

    private var newChatButton: some View {
        // New Thread button with subtle angled glassy effect
        Button(action: {
            newChatButtonTapped.toggle()
            onNewChat()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 16, weight: .medium))
                Text("New Thread")
                    .font(.system(size: 14, weight: .medium))
            }
            .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: newChatButtonTapped)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                ZStack {
                    // Base gradient background
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.accentColor.opacity(0.85),
                            Color.accentColor.opacity(0.75)
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    
                    // Subtle angled glassy overlay effect
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .white.opacity(0.15), location: 0.0),
                            .init(color: .white.opacity(0.05), location: 0.4),
                            .init(color: .clear, location: 0.6),
                            .init(color: .black.opacity(0.03), location: 1.0)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    
                    // Very subtle material texture
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                        .opacity(0.05)
                        .blendMode(.overlay)
                }
            )
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                Color.accentColor.opacity(0.15)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.accentColor.opacity(0.2), radius: 1.5, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 3)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
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
        HStack(spacing: 12) {
            // Select All/None button
            Button(action: {
                if selectedChatIDs.count == filteredChats.count {
                    selectedChatIDs.removeAll()
                    lastSelectedChatID = nil
                } else {
                    selectedChatIDs = Set(filteredChats.map { $0.id })
                    lastSelectedChatID = filteredChats.last?.id
                }
            }) {
                Image(systemName: selectedChatIDs.count == filteredChats.count ? "checklist" : "checklist.unchecked")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.accentColor)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help(selectedChatIDs.count == filteredChats.count ? "Deselect All" : "Select All")
            
            // Delete button
            Button(action: {
                deleteSelectedChats()
            }) {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.red)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Delete Selected")
            .disabled(selectedChatIDs.isEmpty)
            
            // Clear selection button
            Button(action: {
                selectedChatIDs.removeAll()
                lastSelectedChatID = nil
            }) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .help("Clear Selection")
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
        .cornerRadius(8)
    }

    private func deleteSelectedChats() {
        guard !selectedChatIDs.isEmpty else { return }
        
        let alert = NSAlert()
        alert.messageText = "Delete \(selectedChatIDs.count) chat\(selectedChatIDs.count == 1 ? "" : "s")?"
        alert.informativeText = "Are you sure you want to delete the selected chats? This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
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

    private func handleKeyboardSelection(chatID: UUID, isCommandPressed: Bool, isShiftPressed: Bool) {
        if isCommandPressed {
            // Command+click: toggle selection
            if selectedChatIDs.contains(chatID) {
                selectedChatIDs.remove(chatID)
            } else {
                selectedChatIDs.insert(chatID)
                lastSelectedChatID = chatID
            }
        } else if isShiftPressed, let lastID = lastSelectedChatID {
            // Shift+click: select range from last selected to current
            if let startIndex = filteredChats.firstIndex(where: { $0.id == lastID }),
               let endIndex = filteredChats.firstIndex(where: { $0.id == chatID }) {
                let range = min(startIndex, endIndex)...max(startIndex, endIndex)
                for chat in filteredChats[range] {
                    selectedChatIDs.insert(chat.id)
                }
            }
        } else {
            // Regular selection handling
            if selectedChatIDs.contains(chatID) {
                selectedChatIDs.remove(chatID)
            } else {
                selectedChatIDs.insert(chatID)
                lastSelectedChatID = chatID
            }
        }
    }
    
    // MARK: - Section Views
    
    private var projectsSection: some View {
        Group {
            // Projects header
            if !store.getActiveProjects().isEmpty || !getArchivedProjects().isEmpty {
                Section {
                    EmptyView()
                } header: {
                    projectsHeader
                }
            }
            
            // Active projects - each as individual list item
            ForEach(store.getActiveProjects(), id: \.objectID) { project in
                ProjectRowInList(
                    project: project,
                    selectedChat: $selectedChat,
                    selectedProject: $selectedProject,
                    searchText: $searchText,
                    showingCreateProject: $showingCreateProject,
                    showingEditProject: $showingEditProject,
                    projectToEdit: $projectToEdit,
                    onNewChatInProject: { project in
                        let uuid = UUID()
                        let newChat = ChatEntity(context: viewContext)
                        
                        newChat.id = uuid
                        newChat.newChat = true
                        newChat.temperature = 0.8
                        newChat.top_p = 1.0
                        newChat.behavior = "default"
                        newChat.newMessage = ""
                        newChat.createdDate = Date()
                        newChat.updatedDate = Date()
                        newChat.systemMessage = AppConstants.chatGptSystemMessage
                        newChat.name = "New Chat"
                        
                        // Save the chat first to ensure it exists in the database
                        try? viewContext.save()
                        
                        // Then move it to the project
                        store.moveChatsToProject(project, chats: [newChat])
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
    
    private var projectsHeader: some View {
        HStack {
            Text("Projects")
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                showingCreateProject = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .help("Create New Project")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                ForEach(getArchivedProjects(), id: \.objectID) { project in
                    ProjectRowInList(
                        project: project,
                        selectedChat: $selectedChat,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
                        showingCreateProject: $showingCreateProject,
                        showingEditProject: $showingEditProject,
                        projectToEdit: $projectToEdit,
                        onNewChatInProject: { project in
                            let uuid = UUID()
                            let newChat = ChatEntity(context: viewContext)
                            
                            newChat.id = uuid
                            newChat.newChat = true
                            newChat.temperature = 0.8
                            newChat.top_p = 1.0
                            newChat.behavior = "default"
                            newChat.newMessage = ""
                            newChat.createdDate = Date()
                            newChat.updatedDate = Date()
                            newChat.systemMessage = AppConstants.chatGptSystemMessage
                            newChat.name = "New Chat"
                            
                            // Save the chat first to ensure it exists in the database
                            try? viewContext.save()
                            
                            // Then move it to the project
                            store.moveChatsToProject(project, chats: [newChat])
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
            // If there are projects, show "No Project" header first
            if !store.getActiveProjects().isEmpty && !chatsWithoutProject.isEmpty {
                Section {
                    EmptyView()
                } header: {
                    HStack {
                        Text("No Project")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                }
            }
            
            // Show date-grouped chats
            ForEach(DateGroup.allCases, id: \.self) { dateGroup in
                if let chatsInGroup = groupedChatsWithoutProject[dateGroup], !chatsInGroup.isEmpty {
                    Section {
                        ForEach(chatsInGroup, id: \.objectID) { chat in
                            ChatListRow(
                                chat: chat,
                                selectedChat: $selectedChat,
                                viewContext: viewContext,
                                searchText: searchText,
                                isSelectionMode: !selectedChatIDs.isEmpty,
                                isSelected: selectedChatIDs.contains(chat.id),
                                onSelectionToggle: { chatID, isSelected in
                                    if isSelected {
                                        selectedChatIDs.insert(chatID)
                                    } else {
                                        selectedChatIDs.remove(chatID)
                                    }
                                },
                                onKeyboardSelection: { chatID, isCmd, isShift in
                                    handleKeyboardSelection(chatID: chatID, isCommandPressed: isCmd, isShiftPressed: isShift)
                                }
                            )
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
