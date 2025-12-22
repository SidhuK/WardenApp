import SwiftUI
import CoreData
import os

struct ProjectSummaryView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var store: ChatStore
    
    @ObservedObject var project: ProjectEntity
    
    // State for sheet presentations
    @State private var showingMoveToProject = false
    @State private var selectedChatForMove: ChatEntity?
    @State private var newChatButtonTapped = false
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }
    
    @State private var recentChats: [ChatEntity] = []
    @State private var messageCount: Int = 0
    @State private var activeDays: Int = 0
    @State private var isLoadingStats = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                // Horizontal project header layout
                horizontalProjectHeader
                
                // Recent activity
                recentActivitySection
                
                // Bottom compact cards - Stats and Insights
                bottomCompactSection
                
                Spacer(minLength: 100)
            }
            .padding(24)
        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(project.name ?? "Project Summary")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
        }
        .sheet(isPresented: $showingMoveToProject) {
            if let chatToMove = selectedChatForMove {
                MoveToProjectView(
                    chats: [chatToMove],
                    onComplete: {
                        // Refresh or update as needed
                        selectedChatForMove = nil
                    }
                )
            }
        }

        .task {
            // Must launch a new task to perform async work
            await loadProjectData()
        }
    }
    
    // Marked explicitly as @MainActor to safely update state
    @MainActor
    private func loadProjectData() async {
        isLoadingStats = true
        
        let context = viewContext
        let projectId = project.objectID
        
        // Move heavy Core Data work to a background thread, but return data to MainActor
        let result = await Task.detached(priority: .userInitiated) { () -> (chats: [ChatEntity], count: Int, days: Int)? in
            // Create a background context for thread safety if viewing complex graphs
            // But here "project" is passed in.
            // Safer pattern: use perform on the viewContext but return values.
            
            return await context.perform { () -> (chats: [ChatEntity], count: Int, days: Int) in
                 // Re-fetch project to be safe or just use ID if passing across contexts
                 // Since we are inside viewContext.perform, we can use the context.
                 
                 // Fetch recent chats (limit 5)
                 let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
                 request.predicate = NSPredicate(format: "project == %@", context.object(with: projectId))
                 request.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
                 request.fetchLimit = 5
                 
                 // Fetch oldest chat date for days active
                 let oldestRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
                 oldestRequest.predicate = NSPredicate(format: "project == %@", context.object(with: projectId))
                 oldestRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: true)]
                 oldestRequest.fetchLimit = 1

                 var chats: [ChatEntity] = []
                 var count = 0
                 var days = 0

                 do {
                     chats = try context.fetch(request)
                     // Simple count query locally or via helper if thread-safe
                     // We'll reproduce the count logic here to be safe within the context block
                     let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
                     countRequest.predicate = NSPredicate(format: "chat.project == %@", context.object(with: projectId))
                     countRequest.resultType = .countResultType
                     count = try context.count(for: countRequest)
                     
                     if let newest = chats.first?.updatedDate,
                        let oldest = try context.fetch(oldestRequest).first?.createdDate {
                         days = Calendar.current.dateComponents([.day], from: oldest, to: newest).day ?? 0
                     }
                 } catch {
                     WardenLog.coreData.error("Error loading project summary: \(error.localizedDescription)")
                 }
                 
                 return (chats, count, days)
            }
        }.value
        
        if let data = result {
             self.recentChats = data.chats
             self.messageCount = data.count
             self.activeDays = data.days
        }
        self.isLoadingStats = false
    }
    
    private var horizontalProjectHeader: some View {
        HStack(alignment: .top, spacing: 24) {
            Spacer()
            
            // Right side - Project info
            VStack(alignment: .trailing, spacing: 16) {
                // Project icon aligned to the right
                HStack {
                    Spacer()
                    Image(systemName: "folder.fill")
                        .font(.system(size: 48))
                        .foregroundColor(projectColor)
                }
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text(project.name ?? "Untitled Project")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.trailing)
                    
                    if let description = project.projectDescription, !description.isEmpty {
                        Text(description)
                            .font(.title3)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                }
                
                HStack(spacing: 20) {
                    if project.isArchived {
                        Label("Archived", systemImage: "archivebox")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.orange.opacity(0.1))
                            )
                    }
                    
                    Label("Created \(project.createdAt ?? Date(), style: .date)", systemImage: "calendar")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                

            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var bottomCompactSection: some View {
        // Stats Card only
        compactStatsCard
    }
    
    private var compactStatsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Project Stats")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            // 2x2 Grid Layout
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 16),
                GridItem(.flexible(), spacing: 16)
            ], spacing: 12) {
                // Row 1, Column 1
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chats")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(project.chats?.count ?? 0)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Row 1, Column 2
                VStack(alignment: .leading, spacing: 4) {
                    Text("Messages")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(messageCount)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Row 2, Column 1
                VStack(alignment: .leading, spacing: 4) {
                    Text("Days Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(activeDays)")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Row 2, Column 2
                if let lastActivity = recentChats.first?.updatedDate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(formatDateString(lastActivity))
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Activity")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("No activity")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.clear)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    

    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // New Thread button above Recent Activity heading
            if !project.isArchived {
                HStack {
                    newChatButton
                    Spacer()
                }
                .padding(.bottom, 8)
            }
            
            Text("Recent Activity")
                .font(.title2)
                .fontWeight(.semibold)
            
            if recentChats.isEmpty && !isLoadingStats {
                ProjectEmptyStateView(
                    icon: "message",
                    title: "No Chats Yet",
                    description: "Add some chats to this project to see activity here.",
                    action: nil
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(recentChats, id: \.objectID) { chat in
                        Button(action: {
                            // Post notification to select the chat
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SelectChatFromProjectSummary"),
                                object: chat
                            )
                        }) {
                            HStack {
                                // AI Model Logo (same as regular chats) - aligned with proper padding
                                Image("logo_\(chat.apiService?.type ?? "")")
                                    .resizable()
                                    .renderingMode(.template)
                                    .interpolation(.high)
                                    .frame(width: 16, height: 16)
                                    .foregroundColor(.primary)
                                    .padding(.leading, 8)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(chat.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .lineLimit(1)
                                        .foregroundColor(.primary)
                                    
                                    if let lastMessage = chat.lastMessage {
                                        Text(lastMessage.body)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                                
                                Spacer()
                                
                                Text(chat.updatedDate, style: .date)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.clear, lineWidth: 2)
                        )
                        .contextMenu {
                            chatContextMenu(for: chat)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Computed Properties
    
    // Removed computed properties totalMessages and daysActive in favor of async loaded state
    

    

    
    // MARK: - UI Components
    
    private var newChatButton: some View {
        Button(action: {
            newChatButtonTapped.toggle()
            createNewChatInProject()
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
                    // Base gradient background with project color
                    LinearGradient(
                        gradient: Gradient(colors: [
                            projectColor.opacity(0.85),
                            projectColor.opacity(0.75)
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
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.ultraThinMaterial)
                        .opacity(0.05)
                        .blendMode(.overlay)
                }
            )
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.white.opacity(0.2),
                                projectColor.opacity(0.2)
                            ]),
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: projectColor.opacity(0.25), radius: 2, x: 0, y: 1)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PlainButtonStyle())
        .frame(maxWidth: 240)
    }
    
    // MARK: - Helper Methods
    
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func createNewChatInProject() {
        
        let newChat = store.createChat(in: project)
        
        // Post notification to select the new chat
        NotificationCenter.default.post(
            name: NSNotification.Name("SelectChatFromProjectSummary"),
            object: newChat
        )
    }
    
    // MARK: - Context Menu
    
    private func chatContextMenu(for chat: ChatEntity) -> some View {
        Group {
            Button(action: { 
                togglePinChat(chat) 
            }) {
                Label(chat.isPinned ? "Unpin" : "Pin", systemImage: chat.isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat(chat) }) {
                Label("Rename", systemImage: "pencil")
            }
            
            if chat.apiService?.generateChatNames ?? false {
                Button(action: {
                    regenerateChatName(chat)
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            
            Button(action: { clearChat(chat) }) {
                Label("Clear Chat", systemImage: "eraser")
            }
            
            Divider()
            
            Button(action: { 
                selectedChatForMove = chat
                showingMoveToProject = true 
            }) {
                Label("Move to Project", systemImage: "folder.badge.plus")
            }
            
            Divider()
            
            Button(action: { deleteChat(chat) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    // MARK: - Context Menu Actions
    
    private func togglePinChat(_ chat: ChatEntity) {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            WardenLog.coreData.error("Error toggling pin status: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func renameChat(_ chat: ChatEntity) {
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
                        WardenLog.coreData.error("Error renaming chat: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }
    
    private func regenerateChatName(_ chat: ChatEntity) {
        store.regenerateChatName(chat: chat)
    }
    
    private func clearChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Clear Chat?"
        alert.informativeText = "Are you sure you want to delete all messages from \"\(chat.name)\"? Chat parameters will not be deleted. This action cannot be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                chat.clearMessages()
                do {
                    try viewContext.save()
                } catch {
                    WardenLog.coreData.error("Error clearing chat: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    private func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete Chat?"
        alert.informativeText = "Are you sure you want to delete \"\(chat.name)\"? This action cannot be undone."
        alert.alertStyle = .warning
        
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                viewContext.delete(chat)
                do {
                    try viewContext.save()
                } catch {
                    WardenLog.coreData.error("Error deleting chat: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

    }
}


// MARK: - Supporting Views

private struct ProjectEmptyStateView: View {
    let icon: String
    let title: String
    let description: String
    let action: (String, () -> Void)?
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            
            if let action = action {
                Button(action: action.1) {
                    Text(action.0)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}

#Preview {
    if let sampleProject = PreviewStateManager.shared.sampleProject {
        ProjectSummaryView(project: sampleProject)
            .environmentObject(PreviewStateManager.shared.chatStore)
            .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
    } else {
        Text("No sample project available")
    }
} 
