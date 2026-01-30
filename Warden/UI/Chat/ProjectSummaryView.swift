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
    
    private var projectColor: Color {
        Color(hex: project.colorCode ?? "#007AFF") ?? .accentColor
    }

    @State private var allChats: [ChatEntity] = []
    @State private var messageCount: Int = 0
    @State private var activeDays: Int = 0
    @State private var isLoadingStats = true
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Horizontal project header layout
                horizontalProjectHeader

                // Two-column layout: Stats on left, Chats on right
                HStack(alignment: .top, spacing: 24) {
                    // Left column - Stats box
                    statsBox
                        .frame(width: 280)

                    // Right column - All Chats
                    allChatsSection
                }

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

        .task(id: project.id) {
            // Must launch a new task to perform async work
            // Using task(id:) to ensure data reloads when switching between projects
            await loadProjectData()
        }
    }

    // MARK: - Stats Box (Left Column)

    private var statsBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            statRow(title: "Total Chats", value: "\(project.chats?.count ?? 0)", icon: "bubble.left.and.bubble.right")
            Divider().padding(.leading, 40)
            statRow(title: "Messages", value: "\(messageCount)", icon: "text.bubble")
            Divider().padding(.leading, 40)
            statRow(title: "Days Active", value: "\(activeDays)", icon: "calendar")
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }

    private func statRow(title: String, value: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
    
    // Marked explicitly as @MainActor to safely update state
    @MainActor
    private func loadProjectData() async {
        isLoadingStats = true

        // Use project UUID for cross-context queries - more reliable than objectID
        guard let projectUUID = project.id else {
            isLoadingStats = false
            return
        }

        // Do Core Data work on a background context and return objectIDs + primitives back to MainActor.
        let backgroundContext = PersistenceController.shared.container.newBackgroundContext()
        let result = await backgroundContext.perform { () -> (chatIDs: [NSManagedObjectID], count: Int, days: Int)? in
            let request = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
            // Use project.id comparison instead of object comparison for cross-context safety
            request.predicate = NSPredicate(format: "project.id == %@", projectUUID as CVarArg)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.updatedDate, ascending: false)]

            let oldestRequest = NSFetchRequest<ChatEntity>(entityName: "ChatEntity")
            oldestRequest.predicate = NSPredicate(format: "project.id == %@", projectUUID as CVarArg)
            oldestRequest.sortDescriptors = [NSSortDescriptor(keyPath: \ChatEntity.createdDate, ascending: true)]
            oldestRequest.fetchLimit = 1

            var chatIDs: [NSManagedObjectID] = []
            var count = 0
            var days = 0

            do {
                let chats = try backgroundContext.fetch(request)
                chatIDs = chats.map(\.objectID)

                let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "MessageEntity")
                countRequest.predicate = NSPredicate(format: "chat.project.id == %@", projectUUID as CVarArg)
                countRequest.resultType = .countResultType
                count = try backgroundContext.count(for: countRequest)

                if let newest = chats.first?.updatedDate,
                    let oldest = try backgroundContext.fetch(oldestRequest).first?.createdDate
                {
                    days = Calendar.current.dateComponents([.day], from: oldest, to: newest).day ?? 0
                }
            } catch {
                WardenLog.coreData.error("Error loading project summary: \(error.localizedDescription)")
                return nil
            }

            return (chatIDs, count, days)
        }

        if let data = result {
            let chats = data.chatIDs.compactMap { viewContext.object(with: $0) as? ChatEntity }
            allChats = chats
            messageCount = data.count
            activeDays = data.days
        }
        self.isLoadingStats = false
    }
    
    private var horizontalProjectHeader: some View {
        HStack(alignment: .top, spacing: 24) {
             // Hero Icon on the left - simplified without background
             Image(systemName: "folder.fill")
                 .font(.system(size: 48))
                 .foregroundStyle(projectColor)
                 .frame(width: 64, height: 64)
            
            // Project Identity
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name ?? "Untitled Project")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                
                HStack(spacing: 12) {
                    if project.isArchived {
                        Text("Archived")
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .foregroundStyle(.secondary)
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

    private var allChatsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Chats")
                .font(.title3)
                .fontWeight(.semibold)

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
                                 name: .selectChatFromProjectSummary,
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
            createNewChatInProject()
        }) {
            HStack(spacing: 8) {
                Image(systemName: "plus.bubble")
                    .font(.system(size: 14, weight: .medium))
                Text("New Chat")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor)
            )
        }
        .buttonStyle(.plain)
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
            name: .selectChatFromProjectSummary,
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

    @MainActor
    private func presentAlert(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
    
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
        
        presentAlert(alert) { response in
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
        
        presentAlert(alert) { response in
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
        
        presentAlert(alert) { response in
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
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
