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
    @State private var allChats: [ChatEntity] = []
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
                
                // All Chats List
                allChatsSection
                
                Spacer(minLength: 100)
            }
            .padding(24)
        }
        .navigationTitle("")
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
                 // Fetch all chats updated recently
                 let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
                 request.predicate = NSPredicate(format: "project == %@", context.object(with: projectId))
                 request.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]
                 // request.fetchLimit = 5 // Removed limit to fetch all chats
                 
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
             self.allChats = data.chats
             self.recentChats = Array(data.chats.prefix(3))
             self.messageCount = data.count
             self.activeDays = data.days
        }
        self.isLoadingStats = false
    }
    
    private var horizontalProjectHeader: some View {
        HStack(alignment: .top, spacing: 24) {
             // Hero Icon on the left
             ZStack {
                 RoundedRectangle(cornerRadius: 16)
                     .fill(
                         LinearGradient(
                             colors: [projectColor.opacity(0.15), projectColor.opacity(0.05)],
                             startPoint: .topLeading,
                             endPoint: .bottomTrailing
                         )
                     )
                     .frame(width: 80, height: 80)
                     .overlay(
                         RoundedRectangle(cornerRadius: 16)
                             .strokeBorder(projectColor.opacity(0.2), lineWidth: 1)
                     )
                 
                 Image(systemName: "folder.fill")
                     .font(.system(size: 40))
                     .foregroundStyle(projectColor.gradient)
                     .shadow(color: projectColor.opacity(0.3), radius: 8, x: 0, y: 4)
             }
            
            // Project Identity
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name ?? "Untitled Project")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    if project.isArchived {
                        Text("Archived")
                            .font(.xsCaps)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                    
                    Text("Created \(project.createdAt ?? Date(), style: .date)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                if let description = project.projectDescription, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            
            Spacer()
            
            // Primary Action
            newChatButton
        }
    }
    
    // Custom Font modifier helper (will need to be defined or just generic system font)
    // using .caption.weight(.medium) for xsCaps feel

    
    private var bottomCompactSection: some View {
        HStack(spacing: 16) {
            statCard(title: "Total Chats", value: "\(project.chats?.count ?? 0)", icon: "bubble.left.and.bubble.right.fill", color: .blue)
            statCard(title: "Messages", value: "\(messageCount)", icon: "text.bubble.fill", color: .purple)
            statCard(title: "Days Active", value: "\(activeDays)", icon: "calendar.badge.clock", color: .orange)
        }
    }
    
    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.03), radius: 8, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
        )
    }
    

    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2)
                .fontWeight(.bold)
            
            if recentChats.isEmpty && !isLoadingStats {
                // Show nothing here if empty, empty state is likely handled elsewhere or acceptable
                Text("No recent activity")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280, maximum: 400), spacing: 16)], spacing: 16) {
                    ForEach(recentChats, id: \.objectID) { chat in
                        ChatCard(chat: chat, projectColor: projectColor, showDate: false) {
                            NotificationCenter.default.post(
                                name: NSNotification.Name("SelectChatFromProjectSummary"),
                                object: chat
                            )
                        }
                        .contextMenu {
                            chatContextMenu(for: chat)
                        }
                    }
                }
            }
        }
    }
    
    private var allChatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("All Chats")
                .font(.title2)
                .fontWeight(.bold)
            
             if allChats.isEmpty && !isLoadingStats {
                 ProjectEmptyStateView(
                     icon: "bubble.left.and.bubble.right",
                     title: "No Chats Yet",
                     description: "Start a new conversation to see activity here.",
                     action: ("Create New Chat", { createNewChatInProject() })
                 )
             } else {
                 VStack(spacing: 0) {
                     ForEach(allChats, id: \.objectID) { chat in
                         Button(action: {
                             NotificationCenter.default.post(
                                 name: NSNotification.Name("SelectChatFromProjectSummary"),
                                 object: chat
                             )
                         }) {
                             HStack(spacing: 12) {
                                 Image("logo_\(chat.apiService?.type ?? "")")
                                     .resizable()
                                     .renderingMode(.template)
                                     .interpolation(.high)
                                     .frame(width: 16, height: 16)
                                     .foregroundStyle(.primary)
                                 
                                 Text(chat.name)
                                     .font(.body)
                                     .foregroundStyle(.primary)
                                 
                                 Spacer()
                                 
                                 Text(chat.updatedDate, style: .date)
                                     .font(.caption)
                                     .foregroundStyle(.secondary)
                             }
                             .padding(.vertical, 12)
                             .padding(.horizontal, 16)
                             .contentShape(Rectangle())
                         }
                         .buttonStyle(.plain)
                         .background(
                            Color(NSColor.controlBackgroundColor).opacity(0.5)
                         ) 
                         .contextMenu {
                             chatContextMenu(for: chat)
                         }
                         
                         Divider()
                             .padding(.leading, 16)
                     }
                 }
                 .background(
                     RoundedRectangle(cornerRadius: 12)
                         .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
                         .strokeBorder(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5)
                 )
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
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                Text("New Chat")
                    .font(.system(size: 14, weight: .bold))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(projectColor)
            .foregroundStyle(.white)
            .clipShape(Capsule())
            .shadow(color: projectColor.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .symbolEffect(.bounce.down.wholeSymbol, options: .nonRepeating, value: newChatButtonTapped)
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

struct ChatCard: View {
    let chat: ChatEntity
    let projectColor: Color
    var showDate: Bool = true
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 32, height: 32)
                        
                        Image("logo_\(chat.apiService?.type ?? "")")
                            .resizable()
                            .renderingMode(.template)
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundStyle(Color.accentColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.name)
                            .font(.headline)
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                        // Removed relative time Text
                    }
                    
                    Spacer()
                    
                    if chat.isPinned {
                         Image(systemName: "pin.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(45))
                    }
                }
                
                // Snippet
                if let lastMessage = chat.lastMessage?.body {
                    Text(lastMessage.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                } else {
                    Text("No messages yet")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(isHovered ? 0.08 : 0.04), radius: isHovered ? 12 : 6, x: 0, y: isHovered ? 4 : 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isHovered ? projectColor.opacity(0.5) : Color(NSColor.separatorColor).opacity(0.5), lineWidth: isHovered ? 1 : 0.5)
            )
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
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

extension Font {
    static var xsCaps: Font {
        .caption.weight(.bold)
    }
}
