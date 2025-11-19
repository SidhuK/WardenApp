import Foundation
import SwiftUI

enum MessageElements {
    case text(String)
    case table(header: [String], data: [[String]])
    case code(code: String, lang: String, indent: Int)
    case formula(String)
    case thinking(String, isExpanded: Bool)
    case image(NSImage)
    case file(FileAttachment)
}

struct ChatBubbleContent: Equatable {
    let message: String
    let own: Bool
    let waitingForResponse: Bool?
    let errorMessage: ErrorMessage?
    let systemMessage: Bool
    let isStreaming: Bool
    let isLatestMessage: Bool

    static func == (lhs: ChatBubbleContent, rhs: ChatBubbleContent) -> Bool {
        return lhs.message == rhs.message && lhs.own == rhs.own && lhs.waitingForResponse == rhs.waitingForResponse
            && lhs.systemMessage == rhs.systemMessage && lhs.isStreaming == rhs.isStreaming
            && lhs.isLatestMessage == rhs.isLatestMessage
    }
}

struct ChatBubbleView: View, Equatable {
    let content: ChatBubbleContent
    var message: MessageEntity?
    var color: String?
    var onEdit: (() -> Void)?

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: - Bubble Metrics
    private let bubbleCornerRadius: CGFloat = 13
    private let verticalSpacingCompact: CGFloat = 4   // for same author
    private let verticalSpacingSeparated: CGFloat = 12 // between authors
    @State private var isHovered = false
    @State private var showingDeleteConfirmation = false
    @State private var isCopied = false
    @AppStorage("chatFontSize") private var chatFontSize: Double = 14.0

    private var effectiveFontSize: Double {
        chatFontSize
    }

    static func == (lhs: ChatBubbleView, rhs: ChatBubbleView) -> Bool {
        lhs.content == rhs.content
    }
    
    // Timestamp formatting
    private var formattedTimestamp: String {
        guard let messageEntity = message,
              let timestamp = messageEntity.timestamp else { return "" }
        
        let formatter = DateFormatter()
        let now = Date()
        let calendar = Calendar.current
        
        // Check if it's today
        if calendar.isDate(timestamp, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: timestamp)
        }
        
        // Check if it's yesterday
        if calendar.isDate(timestamp, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: now) ?? now) {
            formatter.dateFormat = "HH:mm"
            return "Yesterday \(formatter.string(from: timestamp))"
        }
        
        // Check if it's within the current week
        let weekAgo = calendar.date(byAdding: .weekOfYear, value: -1, to: now) ?? now
        if timestamp > weekAgo {
            formatter.dateFormat = "E HH:mm"
            return formatter.string(from: timestamp)
        }
        
        // For older messages, show date and time
        formatter.dateFormat = "MMM d, HH:mm"
        return formatter.string(from: timestamp)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .bottom, spacing: 6) {
                if content.own && !content.systemMessage {
                    // Push user messages to the trailing edge
                    Spacer(minLength: 40)
                }

                // Bubble content
                bubbleView
                    .modifier(StreamingPulseModifier(isStreaming: content.isStreaming))

                if content.own && !content.systemMessage {
                    Spacer().frame(width: 4)
                }
            }
            // Ensure the entire row respects role-based horizontal alignment
            .frame(maxWidth: .infinity, alignment: rowAlignment)
            // Apply message arrival animation for new messages
            .messageArrival(duration: 0.35, delay: content.isLatestMessage ? 0 : 0)

            if content.errorMessage == nil && !(content.waitingForResponse ?? false) {
                HStack {
                    if content.own {
                        Spacer()
                        toolbarContent
                            .padding(.trailing, 6)
                    }
                    else {
                        toolbarContent
                            .padding(.leading, 12)
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: content.own ? .trailing : .leading)
                .frame(height: 12)
                .transition(.opacity)
                .opacity(isHovered ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: isHovered)
            }
            else {
                Color.clear
                    .frame(maxWidth: .infinity, alignment: content.own ? .trailing : .leading)
                    .frame(height: 12)
            }
        }
        .padding(.vertical, 8)
        .onHover { isHovered in
            self.isHovered = isHovered
        }
        .alert(isPresented: $showingDeleteConfirmation) {
            Alert(
                title: Text("Delete Message"),
                message: Text("Are you sure you want to delete this message?"),
                primaryButton: .destructive(Text("Delete")) {
                    deleteMessage()
                },
                secondaryButton: .cancel()
            )
        }
    }

    private func copyMessageToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        withAnimation {
            isCopied = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            withAnimation {
                isCopied = false
            }
        }
    }

    private func deleteMessage() {
        guard let messageEntity = message else { return }
        viewContext.delete(messageEntity)
        do {
            try viewContext.save()
        }
        catch {
            print("Error deleting message: \(error)")
        }
    }

    // Role-based row alignment used for both bubble row and its metadata.
    private var rowAlignment: Alignment {
        if content.systemMessage {
            // System messages align with assistant on the leading edge.
            return .leading
        }
        // User on trailing, assistant on leading.
        return content.own ? .trailing : .leading
    }

    private var toolbarContent: some View {
        HStack(spacing: 6) {
            if !content.own, let _ = message {
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppConstants.textTertiary)
            }

            if content.systemMessage {
                ToolbarButton(icon: "pencil", text: "Edit") {
                    onEdit?()
                }
            }

            if content.isLatestMessage && !content.systemMessage {
                ToolbarButton(icon: "arrow.clockwise", text: "Retry") {
                    NotificationCenter.default.post(name: NSNotification.Name("RetryMessage"), object: nil)
                }
            }

            ToolbarButton(icon: isCopied ? "checkmark" : "doc.on.doc", text: "Copy") {
                copyMessageToClipboard(content.message)
            }

            if !content.systemMessage {
                ToolbarButton(icon: "trash", text: "") {
                    showingDeleteConfirmation = true
                }
            }

            if content.own, let _ = message {
                Text(formattedTimestamp)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(AppConstants.textTertiary)
            }
        }
    }
    // MARK: - Semantic Bubble Variants

    @ViewBuilder
    private var bubbleView: some View {
        if let error = content.errorMessage {
            errorBubble(error)
        } else if content.systemMessage {
            systemBubble
        } else if content.own {
            userBubble
        } else {
            assistantBubble
        }
    }

    private var userBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            // User bubbles never show the assistant thinking indicator here.
            if content.waitingForResponse ?? false {
                messageBody
            } else {
                messageBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: bubbleCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
    }

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            if content.waitingForResponse ?? false {
                thinkingView
            } else {
                messageBody
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: bubbleCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }

    private var systemBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            MessageContentView(
                message: content.message,
                isStreaming: content.isStreaming,
                own: false,
                effectiveFontSize: effectiveFontSize,
                colorScheme: colorScheme
            )
            .italic()
            .foregroundColor(AppConstants.textSecondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.9)
                )
        )
    }

    private func errorBubble(_ error: ErrorMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ErrorBubbleView(
                error: error,
                onRetry: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("RetryMessage"),
                        object: nil
                    )
                },
                onIgnore: {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("IgnoreError"),
                        object: nil
                    )
                }
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                .fill(AppConstants.destructive.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .stroke(AppConstants.destructive.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var messageBody: some View {
        MessageContentView(
            message: content.message,
            isStreaming: content.isStreaming,
            own: content.own,
            effectiveFontSize: effectiveFontSize,
            colorScheme: colorScheme
        )
        .foregroundColor(AppConstants.textPrimary)
        .multilineTextAlignment(.leading)
    }

    private var thinkingView: some View {
        // Assistant-style "Thinking" indicator aligned to the leading edge.
        HStack(spacing: 6) {
            Text("Thinking")
                .font(.system(size: 13))
                .foregroundColor(AppConstants.textSecondary)
            Circle()
                .fill(AppConstants.textSecondary)
                .frame(width: 6, height: 6)
                .modifier(PulsatingCircle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PulsatingCircle: ViewModifier {
    @State private var isAnimating = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(isAnimating ? 1.5 : 1.0)
            .opacity(isAnimating ? 0.5 : 1.0)
            .animation(
                reduceMotion
                    ? nil
                    : Animation
                        .easeInOut(duration: 0.8)
                        .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear {
                if !reduceMotion {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Streaming Animation

struct StreamingPulseModifier: ViewModifier {
    let isStreaming: Bool
    @State private var isPulsing = false
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing && isStreaming ? 0.8 : 1.0)
            .animation(
                isStreaming
                    ? (reduceMotion
                        ? nil
                        : Animation.easeInOut(duration: 1.5)
                            .repeatForever(autoreverses: true))
                    : nil,
                value: isPulsing
            )
            .onChange(of: isStreaming) { _, newValue in
                if newValue && !reduceMotion {
                    isPulsing = true
                } else {
                    isPulsing = false
                }
            }
            .onAppear {
                if isStreaming && !reduceMotion {
                    isPulsing = true
                }
            }
    }
}
