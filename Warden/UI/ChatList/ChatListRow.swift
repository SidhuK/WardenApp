import SwiftUI
import os

struct ChatListRow: View {
    // Removed Equatable conformance - it was preventing proper re-renders when selection changed
    @ObservedObject var chat: ChatEntity
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var store: ChatStore
    var searchText: String = ""
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onSelectionToggle: ((UUID, Bool) -> Void)?
    @State private var showingMoveToProject = false
    @State private var isHovered = false
    @State private var isRegeneratingName = false

    @MainActor
    private func presentAlert(_ alert: NSAlert, handler: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            alert.beginSheetModal(for: window, completionHandler: handler)
        } else {
            handler(alert.runModal())
        }
    }
    
    init(
        chat: ChatEntity,
        selectedChat: Binding<ChatEntity?>,
        viewContext: NSManagedObjectContext,
        searchText: String = "",
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onSelectionToggle: ((UUID, Bool) -> Void)? = nil
    ) {
        self._chat = ObservedObject(wrappedValue: chat)
        self._selectedChat = selectedChat
        self.viewContext = viewContext
        self.searchText = searchText
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onSelectionToggle = onSelectionToggle
    }

    private var computedIsActive: Bool {
        guard let selectedChat = selectedChat,
              !chat.isDeleted else {
            return false
        }
        return selectedChat.objectID == chat.objectID
    }

    var body: some View {
        MessageCell(
            chat: chat,
            message: chat.lastMessage?.body ?? "",
            isActive: Binding(get: { computedIsActive }, set: { _ in }),
            viewContext: viewContext,
            searchText: searchText,
            isSelectionMode: isSelectionMode,
            isSelected: isSelected,
            onSelectionToggle: { selected in
                onSelectionToggle?(chat.id, selected)
            }
        )
        .overlay(alignment: .trailing) {
            if isHovered && !isSelectionMode {
                Menu {
                    chatActionsMenuContent
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                        )
                }
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .accessibilityLabel("Chat actions")
                .padding(.trailing, 4)
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteChat(chat)
            } label: {
                Image(systemName: "trash")
            }
            
            Button {
                togglePinChat(chat)
            } label: {
                Image(systemName: chat.isPinned ? "pin.slash" : "pin")
            }
            .tint(.secondary)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                showingMoveToProject = true
            } label: {
                Image(systemName: "folder.badge.plus")
            }
            .tint(.secondary)
            
            Button {
                renameChat(chat)
            } label: {
                Image(systemName: "pencil")
            }
            .tint(.secondary)
            
            Button {
                ChatSharingService.shared.shareChat(chat, format: .markdown)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .tint(.secondary)
        }
        .contextMenu {
            chatActionsMenuContent
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

    func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        presentAlert(alert) { response in
            if response == .alertFirstButtonReturn {
                // Clear selectedChat to prevent accessing deleted item
                if selectedChat?.id == chat.id {
                    selectedChat = nil
                }
                
                viewContext.delete(chat)
                DispatchQueue.main.async {
                    do {
                        try viewContext.save()
                    }
                    catch {
                        WardenLog.coreData.error("Error deleting chat: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
        }
    }

    func renameChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Rename chat"
        alert.informativeText = "Enter new name for this chat"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        textField.stringValue = chat.name
        alert.accessoryView = textField
        presentAlert(alert) { response in
            if response == .alertFirstButtonReturn {
                let newName = textField.stringValue.trimmingCharacters(in: .whitespaces)
                guard !newName.isEmpty else { return }
                
                chat.name = newName
                chat.updatedDate = Date()
                viewContext.saveWithRetry(attempts: 3)
            }
        }
    }
    
    func clearChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Clear chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete all messages from this chat? Chat parameters will not be deleted. This action cannot be undone."
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
    
    func togglePinChat(_ chat: ChatEntity) {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            WardenLog.coreData.error("Error toggling pin status: \(error.localizedDescription, privacy: .public)")
        }
    }

    @ViewBuilder
    private var chatActionsMenuContent: some View {
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
                // Lazily create ChatViewModel only when needed to avoid expensive MessageManager creation for all rows
                isRegeneratingName = true
                let tempViewModel = ChatViewModel(chat: chat, viewContext: viewContext)
                tempViewModel.regenerateChatName()
                // Give it time to complete, then reset state
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    isRegeneratingName = false
                }
            }) {
                if isRegeneratingName {
                    Label("Regenerating...", systemImage: "arrow.clockwise")
                } else {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            .disabled(isRegeneratingName)
        }
        
        Button(action: { clearChat(chat) }) {
            Label("Clear Chat", systemImage: "eraser")
        }
        
        Divider()
        
        Button(action: {
            showingMoveToProject = true
        }) {
            Label("Move to Project", systemImage: "folder.badge.plus")
        }
        
        Menu("Share Chat") {
            Button(action: {
                ChatSharingService.shared.shareChat(chat, format: .markdown)
            }) {
                Label("Share as Markdown", systemImage: "square.and.arrow.up")
            }
            
            Button(action: {
                ChatSharingService.shared.copyChatToClipboard(chat, format: .markdown)
            }) {
                Label("Copy as Markdown", systemImage: "doc.on.doc")
            }
            
            Button(action: {
                ChatSharingService.shared.exportChatToFile(chat, format: .markdown)
            }) {
                Label("Export to File", systemImage: "doc.badge.arrow.up")
            }
        }
        
        Divider()
        
        Button(role: .destructive, action: {
            deleteChat(chat)
        }) {
            Label("Delete", systemImage: "trash")
        }
    }
}
