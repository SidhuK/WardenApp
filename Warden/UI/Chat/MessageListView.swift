import SwiftUI
import CoreData

/// Extracted message list to:
/// - Reduce body size in ChatView
/// - Make rendering behavior easier to tune
/// - Keep scroll/stream logic centralized and testable
struct MessageListView: View {
    let chat: ChatEntity
    let sortedMessages: [MessageEntity]
    let isStreaming: Bool
    let currentError: ErrorMessage?
    let enableMultiAgentMode: Bool
    let isMultiAgentMode: Bool
    @ObservedObject var multiAgentManager: MultiAgentMessageManager
    
    // Tool call status
    let activeToolCalls: [ToolCallStatus]
    let messageToolCalls: [Int64: [ToolCallStatus]]

    // State and coordination passed from ChatView
    @Binding var userIsScrolling: Bool

    // Callbacks
    let onRetryMessage: () -> Void
    let onIgnoreError: () -> Void

    // We accept a ScrollViewProxy via closure-style usage in ChatView
    let scrollView: ScrollViewProxy
    let viewWidth: CGFloat

    @State private var pendingCodeBlocks: Int = 0
    @State private var codeBlocksRendered: Bool = false
    @State private var scrollDebounceWorkItem: DispatchWorkItem?

    var body: some View {
        // Leading-aligned stack; individual bubbles handle their own horizontal position.
        VStack(alignment: .leading, spacing: 0) {
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
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(sortedMessages.indices, id: \.self) { index in
                        let messageEntity = sortedMessages[index]
                        let previous = index > 0 ? sortedMessages[index - 1] : nil
                        let sameAuthorAsPrevious = previous?.own == messageEntity.own

                        let topPadding: CGFloat = sameAuthorAsPrevious ? 4 : 12

                        let bubbleContent = ChatBubbleContent(
                            message: messageEntity.body,
                            own: messageEntity.own,
                            waitingForResponse: messageEntity.waitingForResponse,
                            errorMessage: nil,
                            systemMessage: false,
                            isStreaming: isStreaming && messageEntity.id == sortedMessages.last?.id,
                            isLatestMessage: messageEntity.id == sortedMessages.last?.id
                        )
                        
                        // Show tool calls associated with this AI message (if any)
                        if !messageEntity.own, let toolCalls = messageToolCalls[messageEntity.id], !toolCalls.isEmpty {
                            CompletedToolCallsView(toolCalls: toolCalls)
                                .padding(.top, topPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        ChatBubbleView(content: bubbleContent, message: messageEntity)
                            .id(messageEntity.id)
                            .padding(.top, (messageToolCalls[messageEntity.id] != nil && !messageEntity.own) ? 8 : topPadding)
                            .frame(maxWidth: viewWidth * 0.75, alignment: messageEntity.own ? .trailing : .leading)
                            .frame(maxWidth: .infinity, alignment: messageEntity.own ? .trailing : .leading)
                    }
                }
            }

            // Tool call progress view
            if !activeToolCalls.isEmpty {
                ToolCallProgressView(toolCalls: activeToolCalls)
                    .id("tool-calls")
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if chat.waitingForResponse {
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
                    .transition(.opacity)
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
            }

            // Multi-agent responses (only show in multi-agent mode and when feature is enabled)
            if enableMultiAgentMode,
               isMultiAgentMode,
               (!multiAgentManager.activeAgents.isEmpty || multiAgentManager.isProcessing) {
                MultiAgentResponseView(
                    responses: multiAgentManager.activeAgents,
                    isProcessing: multiAgentManager.isProcessing
                )
                .id("multi-agent-responses")
                .padding(.top, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Extra bottom padding so bubbles do not collide with input
            Spacer()
                .frame(height: 16)
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
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("CodeBlockRendered"))) { _ in
            guard pendingCodeBlocks > 0 else { return }
            pendingCodeBlocks -= 1
            if pendingCodeBlocks == 0 {
                codeBlocksRendered = true
                if let lastMessage = sortedMessages.last {
                    scrollView.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("RetryMessage"))) { _ in
            onRetryMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("IgnoreError"))) { _ in
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
        .onSwipe { event in
            if event.direction == .up {
                userIsScrolling = true
            }
        }
    }
}