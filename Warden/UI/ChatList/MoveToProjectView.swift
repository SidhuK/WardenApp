import SwiftUI
import CoreData

struct MoveToProjectView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    let chats: [ChatEntity]
    let onComplete: () -> Void
    
    @State private var selectedProject: ProjectEntity?
    @State private var showingCreateProject = false
    @State private var searchText = ""
    
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
    
    private var filteredProjects: [ProjectEntity] {
        guard !searchText.isEmpty else { return activeProjects }
        return activeProjects.filter { project in
            (project.name?.lowercased().contains(searchText.lowercased()) ?? false) ||
            (project.projectDescription?.lowercased().contains(searchText.lowercased()) ?? false)
        }
    }
    
    private var chatTitles: String {
        if chats.count == 1 {
            return "\"\(chats.first?.name ?? "Chat")\""
        } else {
            return "\(chats.count) chats"
        }
    }
    
    private var currentProject: ProjectEntity? {
        // If all selected chats are in the same project, return that project
        let projects = Set(chats.compactMap { $0.project })
        return projects.count == 1 ? projects.first : nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection
            
            // Search bar
            searchSection
            
            // Project list - single column, full width, scrollable
            ScrollView {
                LazyVStack(spacing: 10) {
                    // Option to remove from current project
                    if currentProject != nil {
                        removeFromProjectOption
                    }
                    
                    // Project options
                    ForEach(filteredProjects, id: \.id) { project in
                        ProjectOptionRow(
                            project: project,
                            isSelected: selectedProject?.objectID == project.objectID,
                            isCurrentProject: currentProject?.objectID == project.objectID,
                            onSelect: {
                                selectedProject = project
                            }
                        )
                    }
                    
                    // Create new project option (always visible inline)
                    createNewProjectOption
                    
                    // Empty state
                    if filteredProjects.isEmpty && !searchText.isEmpty {
                        emptySearchState
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 12)
        .background(AppConstants.backgroundElevated)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 520,
               minHeight: 420, idealHeight: 520, maxHeight: 640)
        .sheet(isPresented: $showingCreateProject) {
            CreateProjectView(
                onProjectCreated: { project in
                    // Close the sheet, bind new project back and immediately apply selection.
                    selectedProject = project
                    showingCreateProject = false
                },
                onCancel: {
                    showingCreateProject = false
                }
            )
            .frame(minWidth: 520, idealWidth: 640, maxWidth: 720,
                   minHeight: 520, idealHeight: 620, maxHeight: 720)
        }
    }
    
    private var canMove: Bool {
        selectedProject != nil || (currentProject != nil && selectedProject == nil)
    }
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                
                Text("Move \(chatTitles)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Text("Select a project to organize your chat\(chats.count == 1 ? "" : "s"). You can also create a new project or remove from the current project.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(AppConstants.backgroundElevated)
                .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 4)
        )
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    private var searchSection: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField("Search projects...", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !searchText.isEmpty {
                Button(action: {
                    searchText = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
    
    private var removeFromProjectOption: some View {
        Button(action: {
            selectedProject = nil // This will indicate removal from project
        }) {
            HStack(spacing: 12) {
                Image(systemName: "folder.badge.minus")
                    .font(.title3)
                    .foregroundColor(.orange)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Remove from Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Move to \"No Project\" section")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedProject == nil && currentProject != nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(selectedProject == nil && currentProject != nil ? Color.orange.opacity(0.08) : AppConstants.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(selectedProject == nil && currentProject != nil ? Color.orange : Color.clear, lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var createNewProjectOption: some View {
        Button(action: {
            showingCreateProject = true
        }) {
            HStack(spacing: 12) {
                Image(systemName: "plus.circle")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                    .frame(width: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Create New Project")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text("Create a new project for these chats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var emptySearchState: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No projects found")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("No projects match your search. Try a different search term or create a new project.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Create New Project") {
                showingCreateProject = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(AppConstants.backgroundElevated)
        )
    }
    
    private func moveChatsToProject() {
        if selectedProject == nil && currentProject != nil {
            // Remove from current project
            store.moveChatsToProject(nil, chats: chats)
        } else if let targetProject = selectedProject {
            // Move to selected project
            store.moveChatsToProject(targetProject, chats: chats)
        }
        
        onComplete()
        dismiss()
    }
}

struct ProjectOptionRow: View {
    @ObservedObject var project: ProjectEntity
    let isSelected: Bool
    let isCurrentProject: Bool
    let onSelect: () -> Void
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }
    
    private var chatCount: Int {
        project.chats?.count ?? 0
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                // Project color indicator
                Circle()
                    .fill(projectColor)
                    .frame(width: 24, height: 24)
                
                // Project info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(project.name ?? "Untitled Project")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        if isCurrentProject {
                            Text("(Current)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.secondary.opacity(0.1))
                                )
                        }
                        
                        Spacer()
                    }
                    
                    HStack {
                        Text("\(chatCount) chat\(chatCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let description = project.projectDescription, !description.isEmpty {
                            Text("• \(description)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                }
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? projectColor.opacity(0.08) : AppConstants.backgroundElevated)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? projectColor : Color.clear, lineWidth: isSelected ? 1.5 : 0)
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isCurrentProject)
    }
}

#Preview {
    if let sampleChats = PreviewStateManager.shared.sampleProject?.chats?.allObjects as? [ChatEntity] {
        MoveToProjectView(
            chats: Array(sampleChats.prefix(1)),
            onComplete: {}
        )
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
    } else {
        Text("No sample chats available")
    }
}