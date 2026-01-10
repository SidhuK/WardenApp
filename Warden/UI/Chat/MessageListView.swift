import SwiftUI
import CoreData

private struct MessageRowView: View {
    @ObservedObject var message: MessageEntity
    let isStreaming: Bool
    let isLatestMessage: Bool
    let viewWidth: CGFloat
    let topPadding: CGFloat
    let messageToolCalls: [Int64: [WardenToolCallStatus]]
    let onEditMessage: (MessageEntity) -> Void
    
    var body: some View {
        let bubbleContent = ChatBubbleContent(
            message: message.body,
            own: message.own,
            waitingForResponse: message.waitingForResponse,
            errorMessage: nil,
            systemMessage: false,
            isStreaming: isStreaming && isLatestMessage,
            isLatestMessage: isLatestMessage
        )
        
        let entityToolCalls = message.toolCalls
        let displayToolCalls = !entityToolCalls.isEmpty ? entityToolCalls : (messageToolCalls[message.id] ?? [])
        
        if !message.own, !displayToolCalls.isEmpty {
            CompletedToolCallsView(toolCalls: displayToolCalls)
                .padding(.top, topPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        
        ChatBubbleView(
            content: bubbleContent,
            message: message,
            onEdit: message.own ? { onEditMessage(message) } : nil
        )
        .id(message.id)
        .padding(.top, (!displayToolCalls.isEmpty && !message.own) ? 8 : topPadding)
        .frame(maxWidth: viewWidth, alignment: message.own ? .trailing : .leading)
        .frame(maxWidth: .infinity, alignment: message.own ? .trailing : .leading)
    }
}

/// Extracted message list to:
/// - Reduce body size in ChatView
/// - Make rendering behavior easier to tune
/// - Keep scroll/stream logic centralized and testable
struct MessageListView: View {
    @ObservedObject var chat: ChatEntity
    let isStreaming: Bool
    let streamingAssistantText: String
    let currentError: ErrorMessage?
    let enableMultiAgentMode: Bool
    let isMultiAgentMode: Bool
    @ObservedObject var multiAgentManager: MultiAgentMessageManager
    
    @FetchRequest private var fetchedMessages: FetchedResults<MessageEntity>
    
    // Tool call status
    let activeToolCalls: [WardenToolCallStatus]
    let messageToolCalls: [Int64: [WardenToolCallStatus]]

    // State and coordination passed from ChatView
    @Binding var userIsScrolling: Bool

    // Callbacks
    let onRetryMessage: () -> Void
    let onIgnoreError: () -> Void
    let onEditMessage: (MessageEntity) -> Void
    let onContinueWithAgent: (MultiAgentMessageManager.AgentResponse) -> Void

    // We accept a ScrollViewProxy via closure-style usage in ChatView
    let scrollView: ScrollViewProxy
    let viewWidth: CGFloat

    @State private var pendingCodeBlocks: Int = 0
    @State private var codeBlocksRendered: Bool = false
    @State private var scrollDebounceWorkItem: DispatchWorkItem?
    
    init(
        chat: ChatEntity,
        isStreaming: Bool,
        streamingAssistantText: String,
        currentError: ErrorMessage?,
        enableMultiAgentMode: Bool,
        isMultiAgentMode: Bool,
        multiAgentManager: MultiAgentMessageManager,
        activeToolCalls: [WardenToolCallStatus],
        messageToolCalls: [Int64: [WardenToolCallStatus]],
        userIsScrolling: Binding<Bool>,
        onRetryMessage: @escaping () -> Void,
        onIgnoreError: @escaping () -> Void,
        onEditMessage: @escaping (MessageEntity) -> Void,
        onContinueWithAgent: @escaping (MultiAgentMessageManager.AgentResponse) -> Void,
        scrollView: ScrollViewProxy,
        viewWidth: CGFloat
    ) {
        self._chat = ObservedObject(wrappedValue: chat)
        self.isStreaming = isStreaming
        self.streamingAssistantText = streamingAssistantText
        self.currentError = currentError
        self.enableMultiAgentMode = enableMultiAgentMode
        self.isMultiAgentMode = isMultiAgentMode
        self.multiAgentManager = multiAgentManager
        self.activeToolCalls = activeToolCalls
        self.messageToolCalls = messageToolCalls
        self._userIsScrolling = userIsScrolling
        self.onRetryMessage = onRetryMessage
        self.onIgnoreError = onIgnoreError
        self.onEditMessage = onEditMessage
        self.onContinueWithAgent = onContinueWithAgent
        self.scrollView = scrollView
        self.viewWidth = viewWidth
        
        self._fetchedMessages = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \MessageEntity.id, ascending: true)],
            predicate: NSPredicate(format: "chat == %@", chat),
            animation: .default
        )
    }

    var body: some View {
        let sortedMessages = Array(fetchedMessages)
        
        // Leading-aligned stack; individual bubbles handle their own horizontal position.
        LazyVStack(alignment: .leading, spacing: 0) {
            if !chat.systemMessage.isEmpty {
                ChatBubbleView(
                    content: ChatBubbleContent(
                        message: chat.systemMessage,
                        own: false,
                        waitingForResponse: nil,
                        errorMessage: nil,
                        systemMessage: true,
                        isStreaming: false,
                        isLatestMessage: false
                    ),
                    color: chat.persona?.color
               )
                .id("system_message")
                .padding(.bottom, 8)
            }

            if !sortedMessages.isEmpty {
                ForEach(Array(sortedMessages.enumerated()), id: \.element.objectID) { index, messageEntity in
                    let previous = index > 0 ? sortedMessages[index - 1] : nil
                    let sameAuthorAsPrevious = previous?.own == messageEntity.own

                    // Slightly increased spacing for better separation
                    let topPadding: CGFloat = sameAuthorAsPrevious ? 4 : 16
                    
                    MessageRowView(
                        message: messageEntity,
                        isStreaming: isStreaming,
                        isLatestMessage: messageEntity.id == sortedMessages.last?.id,
                        viewWidth: viewWidth,
                        topPadding: topPadding,
                        messageToolCalls: messageToolCalls,
                        onEditMessage: onEditMessage
                    )
                }
            }

            if isStreaming, !streamingAssistantText.isEmpty {
                let bubbleContent = ChatBubbleContent(
                    message: streamingAssistantText,
                    own: false,
                    waitingForResponse: true,
                    errorMessage: nil,
                    systemMessage: false,
                    isStreaming: true,
                    isLatestMessage: true
                )
                
                ChatBubbleView(content: bubbleContent)
                    .id("streaming_message")
                    .frame(maxWidth: viewWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
            }
            
            // Tool call progress view
            if !activeToolCalls.isEmpty {
                ToolCallProgressView(toolCalls: activeToolCalls)
                    .id("tool-calls")
                    .padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if chat.waitingForResponse && !(isStreaming && !streamingAssistantText.isEmpty) {
                let bubbleContent = ChatBubbleContent(
                    message: "",
                    own: false,
                    waitingForResponse: true,
                    errorMessage: nil,
                    systemMessage: false,
                    isStreaming: true,
                    isLatestMessage: false
                )

                ChatBubbleView(content: bubbleContent)
                    .id(-1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16) // Consistent padding
            } else if let error = currentError {
                let bubbleContent = ChatBubbleContent(
                    message: "",
                    own: false,
                    waitingForResponse: false,
                    errorMessage: error,
                    systemMessage: false,
                    isStreaming: false,
                    isLatestMessage: true
                )

                ChatBubbleView(content: bubbleContent)
                    .id(-2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 16)
            }

            // Multi-agent responses (only show in multi-agent mode and when feature is enabled)
            if enableMultiAgentMode,
               isMultiAgentMode,
               (!multiAgentManager.activeAgents.isEmpty || multiAgentManager.isProcessing) {
                MultiAgentResponseView(
                    responses: multiAgentManager.activeAgents,
                    isProcessing: multiAgentManager.isProcessing,
                    onContinue: onContinueWithAgent
                )
                .id("multi-agent-responses")
                .padding(.top, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Extra bottom padding so bubbles do not collide with input
            Spacer()
                .frame(height: 24)
        }
        .onAppear {
            // Optimize: Only check the last message for pending code blocks since that's what affects scroll-to-bottom
            if let lastMessage = sortedMessages.last {
                pendingCodeBlocks = (lastMessage.body.components(separatedBy: "```").count - 1) / 2
                scrollView.scrollTo(lastMessage.id, anchor: .bottom)
            }

            if pendingCodeBlocks == 0 {
                codeBlocksRendered = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .codeBlockRendered)) { _ in
            guard pendingCodeBlocks > 0 else { return }
            pendingCodeBlocks -= 1
            if pendingCodeBlocks == 0 {
                codeBlocksRendered = true
                if let lastMessage = sortedMessages.last {
                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .retryMessage)) { _ in
            onRetryMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ignoreError)) { _ in
            onIgnoreError()
        }
        .onChange(of: sortedMessages.last?.body) { _, _ in
            // Only auto-scroll while streaming and if user has not scrolled away
            guard isStreaming, !userIsScrolling else { return }

            scrollDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                if let lastMessage = sortedMessages.last {
                    withAnimation(.easeOut(duration: 0.25)) {
                        scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            scrollDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
        .onChange(of: streamingAssistantText) { _, _ in
            guard isStreaming, !userIsScrolling, !streamingAssistantText.isEmpty else { return }
            scrollDebounceWorkItem?.cancel()
            let workItem = DispatchWorkItem {
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollView.scrollTo("streaming_message", anchor: .bottom)
                }
            }
            scrollDebounceWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: workItem)
        }
        .onSwipe { event in
            if event.direction == .up {
                userIsScrolling = true
            }
        }
    }
}
