import SwiftUI

struct ChatListRow: View, Equatable {
    static func == (lhs: ChatListRow, rhs: ChatListRow) -> Bool {
        lhs.chat?.id == rhs.chat?.id &&
        lhs.chat?.updatedDate == rhs.chat?.updatedDate &&
        lhs.chat?.name == rhs.chat?.name &&
        lhs.chat?.lastMessage?.body == rhs.chat?.lastMessage?.body &&
        lhs.chat?.isPinned == rhs.chat?.isPinned &&
        lhs.searchText == rhs.searchText &&
        lhs.isSelectionMode == rhs.isSelectionMode &&
        lhs.isSelected == rhs.isSelected &&
        (lhs.selectedChat?.id == rhs.selectedChat?.id)
    }
    let chat: ChatEntity?
    let chatID: UUID  // Store the ID separately
    @Binding var selectedChat: ChatEntity?
    let viewContext: NSManagedObjectContext
    @EnvironmentObject private var store: ChatStore
    var searchText: String = ""
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onSelectionToggle: ((UUID, Bool) -> Void)?
    var onKeyboardSelection: ((UUID, Bool, Bool) -> Void)?
    @StateObject private var chatViewModel: ChatViewModel

    init(
        chat: ChatEntity?,
        selectedChat: Binding<ChatEntity?>,
        viewContext: NSManagedObjectContext,
        searchText: String = "",
        isSelectionMode: Bool = false,
        isSelected: Bool = false,
        onSelectionToggle: ((UUID, Bool) -> Void)? = nil,
        onKeyboardSelection: ((UUID, Bool, Bool) -> Void)? = nil
    ) {
        self.chat = chat
        self.chatID = chat?.id ?? UUID()
        self._selectedChat = selectedChat
        self.viewContext = viewContext
        self.searchText = searchText
        self.isSelectionMode = isSelectionMode
        self.isSelected = isSelected
        self.onSelectionToggle = onSelectionToggle
        self.onKeyboardSelection = onKeyboardSelection
        self._chatViewModel = StateObject(wrappedValue: ChatViewModel(chat: chat!, viewContext: viewContext))
    }

    var isActive: Binding<Bool> {
        Binding<Bool>(
            get: {
                selectedChat?.id == chatID
            },
            set: { newValue in
                if newValue {
                    selectedChat = chat
                }
                else {
                    selectedChat = nil
                }
            }
        )
    }

    var body: some View {
        Button {
            let currentEvent = NSApp.currentEvent
            let isCommandPressed = currentEvent?.modifierFlags.contains(.command) ?? false
            let isShiftPressed = currentEvent?.modifierFlags.contains(.shift) ?? false
            
            if isCommandPressed {
                // Command+click: toggle selection of this item
                onKeyboardSelection?(chatID, isCommandPressed, isShiftPressed)
            } else if isShiftPressed {
                // Shift+click: select range
                onKeyboardSelection?(chatID, isCommandPressed, isShiftPressed)
            } else if isSelectionMode {
                // Regular click in selection mode: toggle selection
                onSelectionToggle?(chatID, !isSelected)
            } else {
                // Regular click: set as selected chat
                selectedChat = chat
            }
        } label: {
            MessageCell(
                chat: chat!,
                timestamp: chat?.lastMessage?.timestamp ?? Date(),
                message: chat?.lastMessage?.body ?? "",
                isActive: isActive,
                viewContext: viewContext,
                searchText: searchText,
                isSelectionMode: isSelectionMode,
                isSelected: isSelected,
                onSelectionToggle: { selected in
                    onSelectionToggle?(chatID, selected)
                }
            )
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            // Delete action (destructive, red)
            Button(role: .destructive) {
                deleteChat(chat!)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            // Pin/Unpin action
            Button {
                togglePinChat(chat!)
            } label: {
                Label(chat!.isPinned ? "Unpin" : "Pin", 
                      systemImage: chat!.isPinned ? "pin.slash" : "pin")
            }
            .tint(chat!.isPinned ? Color(.systemBrown).opacity(0.7) : Color(.systemIndigo).opacity(0.7))
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            // Rename action
            Button {
                renameChat(chat!)
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(Color(.systemTeal).opacity(0.7))
            
            // Share action
            Button {
                ChatSharingService.shared.shareChat(chat!, format: .markdown)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(Color(.systemBlue).opacity(0.7))
            
            // Clear chat action
            Button {
                clearChat(chat!)
            } label: {
                Label("Clear", systemImage: "eraser")
            }
            .tint(Color(.systemOrange).opacity(0.6))
            
            // Regenerate name action (only if supported)
            if chat!.apiService?.generateChatNames ?? false {
                Button {
                    chatViewModel.regenerateChatName()
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .tint(Color(.systemPurple).opacity(0.6))
            }
        }
        .contextMenu {
            Button(action: { 
                togglePinChat(chat!) 
            }) {
                Label(chat!.isPinned ? "Unpin" : "Pin", systemImage: chat!.isPinned ? "pin.slash" : "pin")
            }
            
            Button(action: { renameChat(chat!) }) {
                Label("Rename", systemImage: "pencil")
            }
            if chat!.apiService?.generateChatNames ?? false {
                Button(action: {
                    chatViewModel.regenerateChatName()
                }) {
                    Label("Regenerate Name", systemImage: "arrow.clockwise")
                }
            }
            Button(action: { clearChat(chat!) }) {
                Label("Clear Chat", systemImage: "eraser")
            }
            
            Divider()
            
            Menu("Share Chat") {
                Button(action: {
                    ChatSharingService.shared.shareChat(chat!, format: .markdown)
                }) {
                    Label("Share as Markdown", systemImage: "square.and.arrow.up")
                }
                
                Button(action: {
                    ChatSharingService.shared.copyChatToClipboard(chat!, format: .markdown)
                }) {
                    Label("Copy as Markdown", systemImage: "doc.on.doc")
                }
                
                Button(action: {
                    ChatSharingService.shared.exportChatToFile(chat!, format: .markdown)
                }) {
                    Label("Export to File", systemImage: "doc.badge.arrow.up")
                }
            }
            
            Divider()
            Button(action: { deleteChat(chat!) }) {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    func deleteChat(_ chat: ChatEntity) {
        let alert = NSAlert()
        alert.messageText = "Delete chat \(chat.name)?"
        alert.informativeText = "Are you sure you want to delete this chat?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                // Clear selectedChat to prevent accessing deleted item
                if selectedChat?.id == chat.id {
                    selectedChat = nil
                }
                
                // Remove from Spotlight index before deleting
                store.removeChatFromSpotlight(chatId: chat.id)
                
                viewContext.delete(chat)
                DispatchQueue.main.async {
                    do {
                        try viewContext.save()
                    }
                    catch {
                        print("Error deleting chat: \(error.localizedDescription)")
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
        alert.beginSheetModal(for: NSApp.keyWindow!) { response in
            if response == .alertFirstButtonReturn {
                chat.name = textField.stringValue
                do {
                    try viewContext.save()
                }

                catch {
                    print("Error renaming chat: \(error.localizedDescription)")
                }
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
    
    func togglePinChat(_ chat: ChatEntity) {
        chat.isPinned.toggle()
        do {
            try viewContext.save()
        } catch {
            print("Error toggling pin status: \(error.localizedDescription)")
        }
    }
}
