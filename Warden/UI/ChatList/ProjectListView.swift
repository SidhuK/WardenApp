import SwiftUI
import CoreData
import os

struct ProjectListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
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
                ForEach(activeProjects, id: \.id) { project in
                    ProjectRow(
                        project: project,
                        selectedChat: $selectedChat,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
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
                ForEach(archivedProjects, id: \.id) { project in
                    ProjectRow(
                        project: project,
                        selectedChat: $selectedChat,
                        selectedProject: $selectedProject,
                        searchText: $searchText,
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
        // Removed ineffective background preload
    }
    
    private func optimizePerformanceIfNeeded() {
        // Removed aggressive optimization check
    }
}

struct ProjectRow: View {
    @EnvironmentObject private var store: ChatStore
    @ObservedObject var project: ProjectEntity
    @Binding var selectedChat: ChatEntity?
    @Binding var selectedProject: ProjectEntity?
    @Binding var searchText: String

    let onEditProject: () -> Void
    let onDeleteProject: () -> Void
    let onNewChatInProject: () -> Void
    var isArchived: Bool = false

    @State private var isHovered = false

    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }

    private var isSelected: Bool {
        selectedProject?.objectID == project.objectID
    }

    var body: some View {
        Button(action: {
            if isSelected {
                selectedProject = nil
            } else {
                selectedProject = project
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : projectColor)
                    .frame(width: 16, height: 16)

                Text(project.name ?? "Untitled Project")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : isHovered
                                ? Color.primary.opacity(0.05)
                                : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .opacity(isArchived ? 0.6 : 1.0)
        .contextMenu {
            projectContextMenu
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                onDeleteProject()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                store.setProjectArchived(project, archived: !isArchived)
            } label: {
                Label(isArchived ? "Unarchive" : "Archive",
                      systemImage: isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down")
            }
            .tint(.secondary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                onEditProject()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.secondary)

            Button {
                onNewChatInProject()
            } label: {
                Label("New Chat", systemImage: "plus.message")
            }
            .tint(.secondary)
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

            Divider()

            if isArchived {
                Button("Unarchive Project") {
                    store.setProjectArchived(project, archived: false)
                }
            } else {
                Button("Archive Project") {
                    store.setProjectArchived(project, archived: true)
                }
            }

            Button("Delete Project", role: .destructive) {
                onDeleteProject()
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
    @Binding var selectedProject: ProjectEntity?
    @Binding var searchText: String
    @Binding var showingCreateProject: Bool
    @Binding var showingEditProject: Bool
    @Binding var projectToEdit: ProjectEntity?

    let onNewChatInProject: (ProjectEntity) -> Void
    var isArchived: Bool = false

    @State private var isHovered = false

    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }

    private var isSelected: Bool {
        selectedProject?.objectID == project.objectID
    }

    var body: some View {
        Button(action: {
            if isSelected {
                selectedProject = nil
            } else {
                selectedProject = project
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : projectColor)
                    .frame(width: 16, height: 16)

                Text(project.name ?? "Untitled Project")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isSelected
                            ? Color.accentColor
                            : isHovered
                                ? Color.primary.opacity(0.05)
                                : Color.clear
                    )
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .opacity(isArchived ? 0.6 : 1.0)
        .contextMenu {
            projectContextMenu
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                deleteProject()
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                store.setProjectArchived(project, archived: !isArchived)
            } label: {
                Label(isArchived ? "Unarchive" : "Archive",
                      systemImage: isArchived ? "tray.and.arrow.up" : "tray.and.arrow.down")
            }
            .tint(.secondary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                editProject()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.secondary)

            Button {
                onNewChatInProject(project)
            } label: {
                Label("New Chat", systemImage: "plus.message")
            }
            .tint(.secondary)
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
                    store.setProjectArchived(project, archived: false)
                }
            } else {
                Button("Archive Project") {
                    store.setProjectArchived(project, archived: true)
                }
            }
            
            Button("Delete Project") {
                deleteProject()
            }
        }
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
 
