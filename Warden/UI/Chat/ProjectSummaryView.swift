import SwiftUI
import CoreData

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
    
    private var projectChats: [ChatEntity] {
        guard let chats = project.chats?.allObjects as? [ChatEntity] else { return [] }
        return chats.sorted { $0.updatedDate > $1.updatedDate }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .center, spacing: 32) {
                // Centered project header
                centeredProjectHeader
                
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
    }
    
    private var centeredProjectHeader: some View {
        VStack(alignment: .center, spacing: 16) {
            // Project icon centered
            Image(systemName: "folder.fill")
                .font(.system(size: 48))
                .foregroundColor(projectColor)
            
            VStack(alignment: .center, spacing: 8) {
                Text(project.name ?? "Untitled Project")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                if let description = project.projectDescription, !description.isEmpty {
                    Text(description)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            HStack(spacing: 20) {
                Label("Created \(project.createdAt ?? Date(), style: .date)", systemImage: "calendar")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
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
            }
            
            // New Thread button
            if !project.isArchived {
                newChatButton
                    .padding(.top, 8)
            }
        }
    }
    
    private var bottomCompactSection: some View {
        HStack(alignment: .top, spacing: 16) {
            // Stats Card
            compactStatsCard
            
            // Insights Card
            compactInsightsCard
        }
    }
    
    private var compactStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                Text("Project Stats")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Chats:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(projectChats.count)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Messages:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(totalMessages)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Days Active:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(daysActive)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                if let lastActivity = projectChats.first?.updatedDate {
                    HStack {
                        Text("Last Activity:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDateString(lastActivity))
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var compactInsightsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "lightbulb.fill")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text("Key Insights")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }
            
            VStack(spacing: 8) {
                HStack {
                    Text("Style:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(conversationStyle)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Focus:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(projectFocus)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Activity:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(mostActivePeriod)
                        .font(.caption)
                        .fontWeight(.medium)
                }
                
                HStack {
                    Text("Avg. Length:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(averageMessageLength) chars")
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Activity")
                .font(.title2)
                .fontWeight(.semibold)
            
            if projectChats.isEmpty {
                ProjectEmptyStateView(
                    icon: "message",
                    title: "No Chats Yet",
                    description: "Add some chats to this project to see activity here.",
                    action: nil
                )
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(projectChats.prefix(5)), id: \.objectID) { chat in
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
                                    .fill(Color(NSColor.controlBackgroundColor))
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
    
    private var totalMessages: Int {
        projectChats.reduce(0) { total, chat in
            total + chat.messagesArray.count
        }
    }
    
    private var daysActive: Int {
        guard let firstActivity = projectChats.last?.createdDate,
              let lastActivity = projectChats.first?.updatedDate else {
            return 0
        }
        return Calendar.current.dateComponents([.day], from: firstActivity, to: lastActivity).day ?? 0
    }
    
    private var mostActivePeriod: String {
        if daysActive < 7 {
            return "This week"
        } else if daysActive < 30 {
            return "Recent weeks"
        } else {
            return "Over time"
        }
    }
    
    private var averageMessageLength: Int {
        let totalChars = projectChats.flatMap { $0.messagesArray }.reduce(0) { total, message in
            total + message.body.count
        }
        return totalMessages > 0 ? totalChars / totalMessages : 0
    }
    
    private var conversationStyle: String {
        let avgLength = averageMessageLength
        if avgLength < 50 {
            return "Brief & Direct"
        } else if avgLength < 200 {
            return "Conversational"
        } else {
            return "Detailed"
        }
    }
    
    private var projectFocus: String {
        if let instructions = project.customInstructions, !instructions.isEmpty {
            if instructions.lowercased().contains("code") {
                return "Development"
            } else if instructions.lowercased().contains("research") {
                return "Research"
            } else if instructions.lowercased().contains("writing") {
                return "Writing"
            }
        }
        return "General"
    }
    
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
        .padding(.horizontal, 20)
    }
    
    // MARK: - Helper Methods
    
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    private func createNewChatInProject() {
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
        do {
            try viewContext.save()
        } catch {
            print("Error saving new chat: \(error.localizedDescription)")
            return
        }
        
        // Then move it to the project
        store.moveChatsToProject(project, chats: [newChat])
        
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
            print("Error toggling pin status: \(error.localizedDescription)")
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
                        print("Error renaming chat: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
    
    private func regenerateChatName(_ chat: ChatEntity) {
        // Create a ChatViewModel for this specific chat to use the regenerate functionality
        let chatViewModel = ChatViewModel(chat: chat, viewContext: viewContext)
        chatViewModel.regenerateChatName()
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
                    print("Error clearing chat: \(error.localizedDescription)")
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