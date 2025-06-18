import SwiftUI
import CoreData

struct ProjectListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @State private var expandedProjects: Set<UUID> = []
    
    @Binding var selectedChat: ChatEntity?
    @Binding var selectedProject: ProjectEntity?
    @Binding var searchText: String
    @Binding var showingCreateProject: Bool
    @Binding var showingEditProject: Bool
    @Binding var projectToEdit: ProjectEntity?
    
    let onNewChatInProject: (ProjectEntity) -> Void
    
    @FetchRequest(
        entity: ProjectEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \ProjectEntity.isArchived, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.sortOrder, ascending: true),
            NSSortDescriptor(keyPath: \ProjectEntity.createdAt, ascending: false)
        ],
        animation: .default
    )
    private var projects: FetchedResults<ProjectEntity>
    
    private var activeProjects: [ProjectEntity] {
        projects.filter { !$0.isArchived }
    }
    
    private var archivedProjects: [ProjectEntity] {
        projects.filter { $0.isArchived }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Projects header with create button
            projectsHeader
            
            // Active projects with lazy loading
            if !activeProjects.isEmpty {
                ForEach(activeProjects, id: \.objectID) { project in
                    ProjectRow(
                        project: project,
                        isExpanded: expandedProjects.contains(project.id ?? UUID()),
                        selectedChat: $selectedChat,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
                        onToggleExpansion: {
                            guard let projectId = project.id else { return }
                            if expandedProjects.contains(projectId) {
                                expandedProjects.remove(projectId)
                            } else {
                                expandedProjects.insert(projectId)
                                // Preload project data when expanded for better performance
                                store.preloadProjectData(for: [project])
                            }
                        },
                        onEditProject: {
                            projectToEdit = project
                            showingEditProject = true
                        },
                        onDeleteProject: {
                            deleteProject(project)
                        },
                        onNewChatInProject: {
                            onNewChatInProject(project)
                        }
                    )
                    .onAppear {
                        // Preload next few projects when this one appears
                        preloadNearbyProjects(for: project)
                    }
                }
            }
            
            // Archived projects section (collapsible)
            if !archivedProjects.isEmpty {
                archivedProjectsSection
            }
            
            Spacer()
        }
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
    
    @State private var showingArchivedProjects = false
    
    private var archivedProjectsSection: some View {
        VStack(spacing: 0) {
            // Archived projects header
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
                    
                    Text("(\(archivedProjects.count))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Archived projects list
            if showingArchivedProjects {
                ForEach(archivedProjects, id: \.objectID) { project in
                    ProjectRow(
                        project: project,
                        isExpanded: expandedProjects.contains(project.id ?? UUID()),
                        selectedChat: $selectedChat,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
                        onToggleExpansion: {
                            guard let projectId = project.id else { return }
                            if expandedProjects.contains(projectId) {
                                expandedProjects.remove(projectId)
                            } else {
                                expandedProjects.insert(projectId)
                            }
                        },
                        onEditProject: {
                            projectToEdit = project
                            showingEditProject = true
                        },
                        onDeleteProject: {
                            deleteProject(project)
                        },
                        onNewChatInProject: {
                            onNewChatInProject(project)
                        },
                        isArchived: true
                    )
                }
            }
        }
    }
    
    private func deleteProject(_ project: ProjectEntity) {
        let chatCount = project.chats?.count ?? 0
        
        let alert = NSAlert()
        alert.messageText = "Delete Project \"\(project.name ?? "Untitled")\"?"
        alert.informativeText = chatCount > 0 ? 
            "This project contains \(chatCount) chat\(chatCount == 1 ? "" : "s"). The chats will be moved to \"No Project\" and won't be deleted." : 
            "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                store.deleteProject(project)
            }
        }
    }
    
    // MARK: - Performance Optimization Methods
    
    private func preloadNearbyProjects(for currentProject: ProjectEntity) {
        guard let currentIndex = activeProjects.firstIndex(of: currentProject) else { return }
        
        // Preload next 3 projects for smoother scrolling
        let startIndex = max(0, currentIndex)
        let endIndex = min(activeProjects.count - 1, currentIndex + 3)
        let projectsToPreload = Array(activeProjects[startIndex...endIndex])
        
        Task.detached(priority: .background) {
            await MainActor.run {
                store.preloadProjectData(for: projectsToPreload)
            }
        }
    }
    
    private func optimizePerformanceIfNeeded() {
        Task.detached(priority: .background) {
            let stats = await MainActor.run { store.getPerformanceStats() }
            
            // Optimize if we have too many registered objects
            if stats.registeredObjects > 500 {
                await MainActor.run {
                    store.optimizeMemoryUsage()
                }
            }
        }
    }
}

struct ProjectRow: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var project: ProjectEntity
    let isExpanded: Bool
    @Binding var selectedChat: ChatEntity?
    @Binding var selectedProject: ProjectEntity?
    @Binding var searchText: String
    
    let onToggleExpansion: () -> Void
    let onEditProject: () -> Void
    let onDeleteProject: () -> Void
    let onNewChatInProject: () -> Void
    var isArchived: Bool = false
    
    private var projectChats: [ChatEntity] {
        // Use optimized Core Data query instead of relationship access for better performance
        let chats = store.getChatsInProject(project)
        
        // Apply search filter if needed
        guard !searchText.isEmpty else { return chats }
        
        let searchQuery = searchText.lowercased()
        return chats.filter { chat in
            chat.name.lowercased().contains(searchQuery) ||
            chat.systemMessage.lowercased().contains(searchQuery) ||
            (chat.persona?.name?.lowercased().contains(searchQuery) ?? false)
        }
    }
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }
    
    private var isSelected: Bool {
        selectedProject?.objectID == project.objectID
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Project header row with swipe actions applied here
            projectHeaderRow
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Delete action (destructive, red)
                    Button(role: .destructive) {
                        onDeleteProject()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    
                    // Archive/Unarchive action
                    Button {
                        if isArchived {
                            store.unarchiveProject(project)
                        } else {
                            store.archiveProject(project)
                        }
                    } label: {
                        Label(isArchived ? "Unarchive" : "Archive", 
                              systemImage: isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down")
                    }
                    .tint(Color(.systemOrange).opacity(0.7))
                }
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    // Edit action
                    Button {
                        onEditProject()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .tint(Color(.systemBlue).opacity(0.7))
                    
                    // New chat in project action
                    Button {
                        onNewChatInProject()
                    } label: {
                        Label("New Chat", systemImage: "plus.message")
                    }
                    .tint(Color(.systemGreen).opacity(0.7))
                    
                    // Regenerate chat titles action
                    Button {
                        store.regenerateChatTitlesInProject(project)
                    } label: {
                        Label("Regenerate Titles", systemImage: "arrow.clockwise")
                    }
                    .tint(Color(.systemPurple).opacity(0.7))
                }
                .opacity(isArchived ? 0.7 : 1.0)
            
            // Project chats (when expanded) - separate from swipe actions
            if isExpanded {
                VStack(spacing: 0) {
                    // Chats in project
                    ForEach(projectChats, id: \.objectID) { chat in
                        ProjectChatRow(
                            chat: chat,
                            selectedChat: $selectedChat,
                            searchText: searchText
                        )
                    }
                    
                    // Empty state for projects without chats
                    if projectChats.isEmpty {
                        emptyProjectState
                    }
                }
            }
        }
    }
    
    private var projectHeaderRow: some View {
        // Single button containing folder + name + arrow as one entity
        Button(action: {
            // Combined action: select project and toggle expansion
            if isSelected {
                selectedProject = nil
            } else {
                selectedProject = project
            }
            onToggleExpansion()
        }) {
            HStack(spacing: 12) {
                // Colored folder icon - aligned exactly with AI logos
                Image(systemName: "folder.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(projectColor)
                    .frame(width: 16, height: 16)
                    .padding(.leading, 8) // Same as AI logo alignment
                
                // Project name
                VStack(alignment: .leading) {
                    Text(project.name ?? "Untitled Project")
                        .font(.body)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                .padding(.vertical, 8)
                .padding(.trailing, 8)
                
                Spacer()
                
                // Expansion arrow
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.2), value: isExpanded)
                    .padding(.trailing, 8)
            }
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.primary.opacity(0.08) : (isExpanded ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            projectContextMenu
        }
    }
    
    private var projectContextMenu: some View {
        Group {
            Button("New Chat in Project") {
                onNewChatInProject()
            }
            
            Divider()
            
            Button("Edit Project") {
                onEditProject()
            }
            
            Button("Regenerate Chat Titles") {
                store.regenerateChatTitlesInProject(project)
            }
            
            Divider()
            
            if isArchived {
                Button("Unarchive Project") {
                    store.unarchiveProject(project)
                }
            } else {
                Button("Archive Project") {
                    store.archiveProject(project)
                }
            }
            
            Button("Delete Project") {
                onDeleteProject()
            }
        }
    }
    
    private var emptyProjectState: some View {
        VStack(spacing: 4) {
            Text("No chats in this project")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Start New Chat") {
                onNewChatInProject()
            }
            .font(.caption)
            .foregroundColor(.accentColor)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
}

struct ProjectChatRow: View {
    @ObservedObject var chat: ChatEntity
    @Binding var selectedChat: ChatEntity?
    let searchText: String
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    @State private var isHovered = false
    @State private var showingMoveToProject = false
    @StateObject private var chatViewModel: ChatViewModel
    
    init(chat: ChatEntity, selectedChat: Binding<ChatEntity?>, searchText: String) {
        self.chat = chat
        self._selectedChat = selectedChat
        self.searchText = searchText
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat, viewContext: chat.managedObjectContext!))
    }
    
    private var isSelected: Bool {
        selectedChat?.objectID == chat.objectID
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // AI Model Logo (same as regular chats)
            Image("logo_\(chat.apiService?.type ?? "")")
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: 16, height: 16)
                .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .black) : .primary)
                .padding(.leading, 8)
            
            VStack(alignment: .leading) {
                if !chat.name.isEmpty {
                    HighlightedText(chat.name, highlight: searchText)
                        .font(.body)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)
            
            Spacer()
            
            if chat.isPinned {
                Image(systemName: "pin.fill")
                    .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .black) : .gray)
                    .font(.caption)
                    .padding(.trailing, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedChat = chat
        }
        .contextMenu {
            chatContextMenu
        }
        .sheet(isPresented: $showingMoveToProject) {
            MoveToProjectView(
                chats: [chat],
                onComplete: {
                    // Refresh or update as needed
                }
            )
        }
    }
    
    private var chatContextMenu: some View {
        Group {
            Button(action: { 
                togglePinChat() 
            }) {
                Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat() }) {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.green)
            
            if chat.apiService?.generateChatNames ?? false {
                Button(action: {
                    chatViewModel.regenerateChatName()
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            
            Button(action: { showingMoveToProject = true }) {
                Label("Move to Project", systemImage: "folder")
            }
            
            Divider()
            
            Button(action: { deleteChat() }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func togglePinChat() {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            print("Error toggling pin status: \(error.localizedDescription)")
        }
    }
    
    private func renameChat() {
        // Implementation for renaming chat
        let alert = NSAlert()
        alert.messageText = "Rename Chat"
        alert.informativeText = "Enter a new name for this chat:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = chat.name
        alert.accessoryView = textField
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newName.isEmpty {
                    chat.name = newName
                    do {
                        try viewContext.save()
                    } catch {
                        print("Error renaming chat: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func deleteChat() {
        let alert = NSAlert()
        alert.messageText = "Delete Chat?"
        alert.informativeText = "Are you sure you want to delete \"\(chat.name)\"? This action cannot be undone."
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Clear selection if this chat is selected
            if selectedChat?.objectID == chat.objectID {
                selectedChat = nil
            }
            
            // Remove from Spotlight index before deleting
            store.removeChatFromSpotlight(chatId: chat.id)
            
            viewContext.delete(chat)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting chat: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    ProjectListView(
        selectedChat: .constant(nil),
        selectedProject: .constant(nil),
        searchText: .constant(""),
        showingCreateProject: .constant(false),
        showingEditProject: .constant(false),
        projectToEdit: .constant(nil),
        onNewChatInProject: { _ in }
    )
    .environmentObject(PreviewStateManager.shared.chatStore)
    .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}

// MARK: - ProjectRowInList for use in main List
struct ProjectRowInList: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var project: ProjectEntity
    @Binding var selectedChat: ChatEntity?
    @Binding var selectedProject: ProjectEntity?
    @Binding var searchText: String
    @Binding var showingCreateProject: Bool
    @Binding var showingEditProject: Bool
    @Binding var projectToEdit: ProjectEntity?
    
    let onNewChatInProject: (ProjectEntity) -> Void
    var isArchived: Bool = false
    
    @State private var isExpanded = false
    
    private var projectChats: [ChatEntity] {
        // Use optimized Core Data query instead of relationship access for better performance
        let chats = store.getChatsInProject(project)
        
        // Apply search filter if needed
        guard !searchText.isEmpty else { return chats }
        
        let searchQuery = searchText.lowercased()
        return chats.filter { chat in
            chat.name.lowercased().contains(searchQuery) ||
            chat.systemMessage.lowercased().contains(searchQuery) ||
            (chat.persona?.name?.lowercased().contains(searchQuery) ?? false)
        }
    }
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }
    
    private var isSelected: Bool {
        selectedProject?.objectID == project.objectID
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Project header row - Single button containing folder + name + arrow as one entity
            Button(action: {
                // Combined action: select project and toggle expansion
                if isSelected {
                    selectedProject = nil
                } else {
                    selectedProject = project
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 2) {
                    // Colored folder icon - aligned with AI logo (8pt from left edge)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(projectColor)
                        .padding(.leading, 8) // Align with AI logo
                    
                    // Project name
                    Text(project.name ?? "Untitled Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .padding(.leading, 8) // Add spacing between folder and name
                    
                    Spacer()
                    
                    // Expansion arrow - now part of the same button
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .padding(.trailing, 8)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.primary.opacity(0.08) : (isExpanded ? Color.primary.opacity(0.04) : Color.clear))
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .contextMenu {
                projectContextMenu
            }
            
            // Project chats (when expanded) - separate from swipe actions
            if isExpanded {
                VStack(spacing: 0) {
                    // Chats in project
                    ForEach(projectChats, id: \.objectID) { chat in
                        ProjectChatRowInList(
                            chat: chat,
                            selectedChat: $selectedChat,
                            searchText: searchText
                        )
                    }
                    
                    // Empty state for projects without chats
                    if projectChats.isEmpty {
                        emptyProjectState
                    }
                }
            }
        }
        .opacity(isArchived ? 0.7 : 1.0)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Delete action (destructive, red)
            Button(role: .destructive) {
                deleteProject()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            // Archive/Unarchive action
            Button {
                if isArchived {
                    store.unarchiveProject(project)
                } else {
                    store.archiveProject(project)
                }
            } label: {
                Label(isArchived ? "Unarchive" : "Archive", 
                      systemImage: isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down")
            }
            .tint(Color(.systemOrange).opacity(0.7))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Edit action
            Button {
                editProject()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Color(.systemBlue).opacity(0.7))
            
            // New chat in project action
            Button {
                onNewChatInProject(project)
            } label: {
                Label("New Chat", systemImage: "plus.message")
            }
            .tint(Color(.systemGreen).opacity(0.7))
            
            // Regenerate chat titles action
            Button {
                store.regenerateChatTitlesInProject(project)
            } label: {
                Label("Regenerate Titles", systemImage: "arrow.clockwise")
            }
            .tint(Color(.systemPurple).opacity(0.7))
        }
    }
    
    private var projectContextMenu: some View {
        Group {
            Button("New Chat in Project") {
                onNewChatInProject(project)
            }
            
            Divider()
            
            Button("Edit Project") {
                editProject()
            }
            
            Button("Regenerate Chat Titles") {
                store.regenerateChatTitlesInProject(project)
            }
            
            Divider()
            
            if isArchived {
                Button("Unarchive Project") {
                    store.unarchiveProject(project)
                }
            } else {
                Button("Archive Project") {
                    store.archiveProject(project)
                }
            }
            
            Button("Delete Project") {
                deleteProject()
            }
        }
    }
    
    private var emptyProjectState: some View {
        VStack(spacing: 4) {
            Text("No chats in this project")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Start New Chat") {
                onNewChatInProject(project)
            }
            .font(.caption)
            .foregroundColor(.accentColor)
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 8)
    }
    
    private func editProject() {
        projectToEdit = project
        showingEditProject = true
    }
    
    private func deleteProject() {
        let chatCount = project.chats?.count ?? 0
        
        let alert = NSAlert()
        alert.messageText = "Delete Project \"\(project.name ?? "Untitled")\"?"
        alert.informativeText = chatCount > 0 ? 
            "This project contains \(chatCount) chat\(chatCount == 1 ? "" : "s"). The chats will be moved to \"No Project\" and won't be deleted." : 
            "This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                store.deleteProject(project)
            }
        }
    }
}

// MARK: - ProjectChatRowInList for use in main List
struct ProjectChatRowInList: View {
    @ObservedObject var chat: ChatEntity
    @Binding var selectedChat: ChatEntity?
    let searchText: String
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    @AppStorage("showSidebarAIIcons") private var showSidebarAIIcons: Bool = true
    @State private var isHovered = false
    @State private var showingMoveToProject = false
    @StateObject private var chatViewModel: ChatViewModel
    
    init(chat: ChatEntity, selectedChat: Binding<ChatEntity?>, searchText: String) {
        self.chat = chat
        self._selectedChat = selectedChat
        self.searchText = searchText
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat, viewContext: chat.managedObjectContext!))
    }
    
    private var isSelected: Bool {
        selectedChat?.objectID == chat.objectID
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // AI service logo (conditionally shown) - aligned with project folder icons
            if showSidebarAIIcons {
                if let apiServiceName = chat.apiService?.name,
                   let image = getServiceLogo(for: apiServiceName) {
                    image
                        .resizable()
                        .renderingMode(.template)
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundColor(isSelected ? (colorScheme == .dark ? .white : .black) : .primary)
                        .padding(.leading, 8) // Align with project folder and regular chat icons
                } else {
                    Image(systemName: "message")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                        .padding(.leading, 8) // Align with project folder and regular chat icons
                }
            }
            
            // Chat info
            VStack(alignment: .leading, spacing: 2) {
                Text(getChatDisplayName())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let lastMessage = getLastMessage() {
                    Text(lastMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Pin indicator
            if chat.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selectedChat = chat
        }
        .contextMenu {
            chatContextMenu
        }
        .sheet(isPresented: $showingMoveToProject) {
            // Move to project sheet would go here
        }
    }
    
    private var chatContextMenu: some View {
        Group {
            Button(action: { 
                togglePinChat() 
            }) {
                Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat() }) {
                Label("Rename", systemImage: "pencil")
            }
            
            if chat.apiService?.generateChatNames ?? false {
                Button(action: {
                    chatViewModel.regenerateChatName()
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            
            Button(action: { showingMoveToProject = true }) {
                Label("Move to Project", systemImage: "folder")
            }
            
            Divider()
            
            Button(action: { deleteChat() }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private func getChatDisplayName() -> String {
        if searchText.isEmpty {
            return chat.name
        }
        
        // Return highlighted name if there's a search
        return chat.name
    }
    
    private func getLastMessage() -> String? {
        if let messages = chat.messages.array as? [MessageEntity],
           let lastMessage = messages.last {
            return lastMessage.body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func getServiceLogo(for serviceName: String) -> Image? {
        switch serviceName.lowercased() {
        case "openai", "chatgpt":
            return Image("logo_chatgpt")
        case "anthropic", "claude":
            return Image("logo_claude")
        case "google", "gemini":
            return Image("logo_gemini")
        case "ollama":
            return Image("logo_ollama")
        case "openrouter":
            return Image("logo_openrouter")
        case "perplexity":
            return Image("logo_perplexity")
        case "deepseek":
            return Image("logo_deepseek")
        case "groq":
            return Image("logo_groq")
        case "mistral":
            return Image("logo_mistral")
        case "xai", "grok":
            return Image("logo_xai")
        default:
            return nil
        }
    }
    
    private func togglePinChat() {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            print("Error toggling pin status: \(error.localizedDescription)")
        }
    }
    
    private func renameChat() {
        // Implementation for renaming chat
        let alert = NSAlert()
        alert.messageText = "Rename Chat"
        alert.informativeText = "Enter a new name for this chat:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = chat.name
        alert.accessoryView = textField
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !newName.isEmpty {
                    chat.name = newName
                    do {
                        try viewContext.save()
                    } catch {
                        print("Error renaming chat: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func deleteChat() {
        let alert = NSAlert()
        alert.messageText = "Delete Chat?"
        alert.informativeText = "Are you sure you want to delete \"\(chat.name)\"? This action cannot be undone."
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        if alert.runModal() == .alertFirstButtonReturn {
            // Clear selection if this chat is selected
            if selectedChat?.objectID == chat.objectID {
                selectedChat = nil
            }
            
            // Remove from Spotlight index before deleting
            store.removeChatFromSpotlight(chatId: chat.id)
            
            viewContext.delete(chat)
            do {
                try viewContext.save()
            } catch {
                print("Error deleting chat: \(error.localizedDescription)")
            }
        }
    }
} 