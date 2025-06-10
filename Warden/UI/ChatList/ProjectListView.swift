import SwiftUI
import CoreData

struct ProjectListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @State private var expandedProjects: Set<UUID> = []
    @State private var selectedProjectForEdit: ProjectEntity?
    @State private var showingCreateProject = false
    @State private var showingProjectSettings = false
    
    @Binding var selectedChat: ChatEntity?
    @Binding var searchText: String
    
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
                LazyVStack(spacing: 0) {
                    ForEach(activeProjects, id: \.objectID) { project in
                        ProjectRow(
                            project: project,
                            isExpanded: expandedProjects.contains(project.id ?? UUID()),
                            selectedChat: $selectedChat,
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
                                selectedProjectForEdit = project
                                showingProjectSettings = true
                            },
                            onDeleteProject: {
                                deleteProject(project)
                            },
                            onNewChatInProject: {
                                onNewChatInProject(project)
                            },
                            onGenerateSummary: {
                                generateProjectSummary(project)
                            }
                        )
                        .onAppear {
                            // Preload next few projects when this one appears
                            preloadNearbyProjects(for: project)
                        }
                    }
                }
            }
            
            // Archived projects section (collapsible)
            if !archivedProjects.isEmpty {
                archivedProjectsSection
            }
            
            Spacer()
        }
        .sheet(isPresented: $showingCreateProject) {
            CreateProjectView(onProjectCreated: { project in
                if let projectId = project.id {
                    expandedProjects.insert(projectId)
                }
            })
        }
        .sheet(isPresented: $showingProjectSettings) {
            if let project = selectedProjectForEdit {
                ProjectSettingsView(project: project)
            }
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
                            selectedProjectForEdit = project
                            showingProjectSettings = true
                        },
                        onDeleteProject: {
                            deleteProject(project)
                        },
                        onNewChatInProject: {
                            onNewChatInProject(project)
                        },
                        onGenerateSummary: {
                            generateProjectSummary(project)
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
    
    private func generateProjectSummary(_ project: ProjectEntity) {
        Task {
            do {
                                            await MainActor.run {
                                store.generateProjectSummary(project)
                            }
            } catch {
                print("Error generating summary for project \(project.name ?? "Unknown"): \(error)")
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
    @Binding var searchText: String
    
    let onToggleExpansion: () -> Void
    let onEditProject: () -> Void
    let onDeleteProject: () -> Void
    let onNewChatInProject: () -> Void
    let onGenerateSummary: () -> Void
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
    
    var body: some View {
        VStack(spacing: 0) {
            // Project header
            Button(action: onToggleExpansion) {
                HStack(spacing: 8) {
                    // Expansion chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                        .foregroundColor(.secondary)
                    
                    // Project color indicator
                    Circle()
                        .fill(projectColor)
                        .frame(width: 8, height: 8)
                    
                    // Project name
                    Text(project.name ?? "Untitled Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Chat count and last activity
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(projectChats.count)")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        if let lastActivity = projectChats.first?.updatedDate {
                            Text(lastActivity, style: .relative)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .contextMenu {
                projectContextMenu
            }
            .opacity(isArchived ? 0.7 : 1.0)
            
            // Project summary preview (when collapsed)
            if !isExpanded && !isArchived {
                projectSummaryPreview
            }
            
            // Project chats (when expanded)
            if isExpanded {
                VStack(spacing: 0) {
                    // Project summary (when expanded)
                    if !isArchived {
                        expandedProjectSummary
                    }
                    
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
    
    private var projectContextMenu: some View {
        Group {
            Button("New Chat in Project") {
                onNewChatInProject()
            }
            
            Divider()
            
            Button("Edit Project") {
                onEditProject()
            }
            
            if !isArchived && !(project.aiGeneratedSummary?.isEmpty ?? true) {
                Button("Refresh Summary") {
                    onGenerateSummary()
                }
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
    
    private var projectSummaryPreview: some View {
        Group {
            if let summary = project.aiGeneratedSummary, !summary.isEmpty {
                HStack {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 4)
            }
        }
    }
    
    private var expandedProjectSummary: some View {
        Group {
            if let summary = project.aiGeneratedSummary, !summary.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Project Summary")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button(action: onGenerateSummary) {
                            Image(systemName: "arrow.clockwise")
                                .font(.caption)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Refresh Summary")
                    }
                    
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(.bottom, 4)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(projectColor.opacity(0.05))
                        .padding(.horizontal, 24)
                )
            } else {
                VStack(spacing: 4) {
                    Text("No summary yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button("Generate Summary") {
                        onGenerateSummary()
                    }
                    .font(.caption)
                    .foregroundColor(.accentColor)
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
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
    
    private var isSelected: Bool {
        selectedChat?.objectID == chat.objectID
    }
    
    var body: some View {
        Button(action: {
            selectedChat = chat
        }) {
            HStack(spacing: 8) {
                // Indent indicator
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16)
                
                // Chat icon
                Image(systemName: "message")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                // Chat name
                Text(chat.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .medium : .regular)
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)
                
                Spacer()
                
                // Last activity
                if let lastMessage = chat.lastMessage {
                    Text(lastMessage.timestamp ?? Date(), style: .relative)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}



#Preview {
    ProjectListView(
        selectedChat: .constant(nil),
        searchText: .constant(""),
        onNewChatInProject: { _ in }
    )
    .environmentObject(PreviewStateManager.shared.chatStore)
    .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
} 