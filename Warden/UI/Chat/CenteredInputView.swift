import SwiftUI
import CoreData

struct CenteredInputView: View {
    @Binding var composerState: ComposerState
    @ObservedObject var chat: ChatEntity
    let imageUploadsAllowed: Bool
    let isStreaming: Bool
    
    let enableMultiAgentMode: Bool
    
    let onSendMessage: () -> Void
    let onAddImage: () -> Void
    let onAddFile: () -> Void
    let onAddAssistant: (() -> Void)?
    let onStopStreaming: (() -> Void)?
    var focusToken: Int = 0
    
    @EnvironmentObject private var store: ChatStore
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0
    @State private var isInputFocused = false
    @State private var recentChats: [ChatEntity] = []
    @State private var usedPrompts: [PromptEntity] = []
    @State private var nonEmptyChatCount = 0
    @State private var hasLoadedHome = false
    @State private var stacksPanels = false

    private static let recentChatLimit = 5
    private static let promptLimit = 5
    /// Below this many chats with messages, the starter cards are more useful than history.
    private static let starterCardsChatThreshold = 3
    private static let stackedPanelsWidth: CGFloat = 540
    
    private var effectiveFontSize: Double {
        chatFontSize
    }
    
    private var canSend: Bool {
        !composerState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isComposerEmpty: Bool {
        composerState.attachedImages.isEmpty && composerState.attachedFiles.isEmpty && composerState.text.isEmpty
    }

    private var showsStarterCards: Bool {
        nonEmptyChatCount < Self.starterCardsChatThreshold || (recentChats.isEmpty && usedPrompts.isEmpty)
    }

    private var placeholderText: String {
        let hint = "Type / for prompts, or drop files here"
        guard let modelName = BetterCompactModelSelector.shortModelName(for: chat) else {
            return "Message… \(hint)"
        }
        return "Message \(modelName)… \(hint)"
    }

    /// Reload the home panels when the chat or its project changes.
    private var homeReloadKey: [NSManagedObjectID] {
        [chat.objectID, chat.project?.objectID].compactMap { $0 }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 4) {
                            NewChatContextRow(chat: chat)
                                .padding(.leading, 12)

                            MessageInputView(
                                state: $composerState,
                                chat: chat,
                                imageUploadsAllowed: chat.apiService?.imageUploadsAllowed ?? false,
                                isStreaming: isStreaming,
                                enableMultiAgentMode: enableMultiAgentMode,
                                onEnter: onSendMessage,
                                onAddImage: onAddImage,
                                onAddFile: onAddFile,
                                onAddAssistant: onAddAssistant,
                                onStopStreaming: onStopStreaming,
                                inputPlaceholderText: placeholderText,
                                cornerRadius: 18.0,
                                focusToken: focusToken
                            )
                            .persistsComposerDraft(for: chat, state: $composerState)
                            .padding(6)
                            .scaleEffect(isInputFocused ? 1.01 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isInputFocused)
                            .onReceive(NotificationCenter.default.publisher(for: NSTextField.textDidBeginEditingNotification)) { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isInputFocused = true
                                }
                            }
                            .onReceive(NotificationCenter.default.publisher(for: NSTextField.textDidEndEditingNotification)) { _ in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isInputFocused = false
                                }
                            }
                        }
                        .frame(maxWidth: 1000)
                        
                        if hasLoadedHome && isComposerEmpty {
                            homeContent
                                .frame(maxWidth: 1000)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    Spacer()
                    Spacer()
                }
                .padding(.horizontal, 32)
            }
        }
        .task(id: homeReloadKey) {
            loadHome()
        }
        .animation(.easeInOut(duration: 0.25), value: composerState.text.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: composerState.attachedImages.isEmpty)
        .animation(.easeInOut(duration: 0.25), value: composerState.attachedFiles.isEmpty)
    }

    @ViewBuilder
    private var homeContent: some View {
        VStack(spacing: 20) {
            if showsStarterCards {
                starterCards
            }
            historyPanels
        }
    }

    @ViewBuilder
    private var historyPanels: some View {
        // The lists are snapshots; a chat or prompt deleted elsewhere since loading must not be rendered
        // (reading a non-optional attribute such as `updatedDate` from a deleted object traps).
        let liveChats = recentChats.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        let livePrompts = usedPrompts.filter { !$0.isDeleted && $0.managedObjectContext != nil }
        if !liveChats.isEmpty || !livePrompts.isEmpty {
            let layout = stacksPanels
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            layout {
                if !liveChats.isEmpty {
                    ContinueChatsPanel(
                        chats: liveChats,
                        showsProjectNames: chat.project == nil,
                        onOpen: openChat
                    )
                }
                if !livePrompts.isEmpty {
                    PromptShortcutsPanel(prompts: livePrompts, onSelect: insertPrompt)
                }
            }
            .padding(.horizontal, 6)
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width < Self.stackedPanelsWidth
            } action: { isNarrow in
                stacksPanels = isNarrow
            }
        }
    }

    private var starterCards: some View {
        HStack(spacing: 12) {
            SuggestionCard(
                icon: "lightbulb.max",
                title: "Brainstorm",
                subtitle: "Creative ideas",
                color: .yellow,
                action: { composerState.text = "Give me some creative ideas for " }
            )
            .frame(maxWidth: .infinity)
            
            SuggestionCard(
                icon: "doc.text.image",
                title: "Summarize",
                subtitle: "Long documents",
                color: .blue,
                action: { composerState.text = "Summarize this text: " }
            )
            .frame(maxWidth: .infinity)
            
            SuggestionCard(
                icon: "chevron.left.forwardslash.chevron.right",
                title: "Code",
                subtitle: "Write & debug",
                color: .purple,
                action: { composerState.text = "Write a function that " }
            )
            .frame(maxWidth: .infinity)
            
            SuggestionCard(
                icon: "paintpalette",
                title: "Design",
                subtitle: "UI/UX concepts",
                color: .pink,
                action: { composerState.text = "Design a user interface for " }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private func loadHome() {
        recentChats = store.recentChats(
            in: chat.project,
            // A temporary chat isn't in the store, so it can't be (and needn't be) excluded from the fetch.
            excluding: chat.isTemporary ? nil : chat,
            limit: Self.recentChatLimit
        )
        usedPrompts = PromptLibraryManager.shared.topPrompts(limit: Self.promptLimit).filter { $0.usageCount > 0 }
        nonEmptyChatCount = store.countNonEmptyChats()
        hasLoadedHome = true
    }

    private func openChat(_ target: ChatEntity) {
        NotificationCenter.default.post(
            name: .openChatByID,
            object: nil,
            userInfo: ["chatObjectID": target.objectID]
        )
    }

    private func insertPrompt(_ prompt: PromptEntity) {
        composerState.text = prompt.content
        PromptLibraryManager.shared.recordUse(prompt)
    }
}

struct SuggestionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(isHovered ? 0.15 : 0.08), lineWidth: 0.5)
            )
            .brightness(isHovered ? 0.02 : 0)
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    @Previewable @Environment(\.managedObjectContext) var viewContext
    
    let mockChat = {
        let chat = ChatEntity(context: PersistenceController.preview.container.viewContext)
        chat.id = UUID()
        chat.name = "New Chat"
        chat.systemMessage = ""
        return chat
    }()
    
    CenteredInputView(
        composerState: .constant(ComposerState()),
        chat: mockChat,
        imageUploadsAllowed: true,
        isStreaming: false,
        enableMultiAgentMode: false,
        onSendMessage: {},
        onAddImage: {},
        onAddFile: {},
        onAddAssistant: {},
        onStopStreaming: {}
    )
    .environmentObject(PreviewStateManager.shared)
    .environmentObject(PreviewStateManager.shared.chatStore)
    .frame(width: 800, height: 600)
} 
