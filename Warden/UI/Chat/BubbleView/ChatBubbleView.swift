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
    private let bubbleCornerRadius: CGFloat = 18 // Increased for rounder look
    private let verticalSpacingCompact: CGFloat = 4
    private let verticalSpacingSeparated: CGFloat = 12
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
        
        return timestamp.formattedTimestamp()
    }

    var body: some View {
        VStack(spacing: 4) {
            bubbleRow
            toolbarRow
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
    
    private var bubbleRow: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if !content.own && !content.systemMessage {
                aiProviderLogo
                    .frame(width: 24, height: 24) // Slightly larger avatar
            }
            
            if content.own && !content.systemMessage {
                Spacer(minLength: 40)
            }

            bubbleView
                .modifier(StreamingPulseModifier(isStreaming: content.isStreaming))

            if content.own && !content.systemMessage {
                // No user avatar for iMessage style, just the bubble on the right
                // But we can keep it if desired, or remove it to be more like iMessage
                // User request said "like iMessage", which doesn't show user avatar usually.
                // But let's keep it consistent with the app for now, maybe smaller or hidden?
                // The image shows user avatar. So we keep it.
                userAvatar
                    .frame(width: 24, height: 24)
            }
        }
        .frame(maxWidth: .infinity, alignment: rowAlignment)
        .messageArrival(duration: 0.35, delay: content.isLatestMessage ? 0 : 0)
    }
    
    private var toolbarRow: some View {
        Group {
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
            unifiedBubble(role: .error(error))
        } else if content.systemMessage {
            unifiedBubble(role: .system)
        } else if content.own {
            unifiedBubble(role: .user)
        } else {
            unifiedBubble(role: .assistant)
        }
    }
    
    // MARK: - Unified Bubble Renderer
    
    private enum BubbleRole {
        case user
        case assistant
        case system
        case error(ErrorMessage)
        
        var isUser: Bool {
            if case .user = self { return true }
            return false
        }
    }
    
    @ViewBuilder
    private func unifiedBubble(role: BubbleRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            bubbleContent(for: role)
        }
        .padding(.horizontal, 14) // Slightly increased padding
        .padding(.vertical, 10)
        .background(bubbleBackground(for: role))
        .clipShape(BubbleShape(myMessage: role.isUser)) // Custom shape
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    @ViewBuilder
    private func bubbleBackground(for role: BubbleRole) -> some View {
        switch role {
        case .user:
            Color.accentColor
        case .assistant:
            Color(nsColor: .controlBackgroundColor) // Grayish/System background
        case .system:
            Color.accentColor.opacity(0.1)
        case .error:
            AppConstants.destructive.opacity(0.1)
        }
    }
    
    @ViewBuilder
    private func bubbleContent(for role: BubbleRole) -> some View {
        switch role {
        case .user:
            if content.waitingForResponse ?? false {
                messageBody
                    .foregroundColor(.white)
            } else {
                messageBody
                    .foregroundColor(.white)
            }
            
        case .assistant:
            if content.waitingForResponse ?? false {
                thinkingView
            } else {
                messageBody
                    .foregroundColor(AppConstants.textPrimary)
            }
            
        case .system:
            MessageContentView(
                message: content.message,
                isStreaming: content.isStreaming,
                own: false,
                effectiveFontSize: effectiveFontSize,
                colorScheme: colorScheme
            )
            .italic()
            .foregroundColor(AppConstants.textSecondary)
            
        case .error(let error):
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
                },
                onGoToSettings: nil
            )
        }
    }

    private var messageBody: some View {
        MessageContentView(
            message: content.message,
            isStreaming: content.isStreaming,
            own: content.own,
            effectiveFontSize: effectiveFontSize,
            colorScheme: colorScheme
        )
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
    
    private var userAvatar: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)
            
            Image(systemName: "person.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
    
    private var aiProviderLogo: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 0.5)
                )
            
            if let apiService = message?.chat?.apiService,
               let providerType = apiService.type {
                let iconName = providerIconName(for: providerType)
                if iconName == "sparkles" {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                } else {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 14, height: 14)
                        .foregroundColor(.accentColor)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    private func providerIconName(for provider: String) -> String {
        let lowerProvider = provider.lowercased()
        switch lowerProvider {
        case _ where lowerProvider.contains("openai"):
            return "logo_chatgpt"
        case _ where lowerProvider.contains("anthropic"):
            return "logo_claude"
        case _ where lowerProvider.contains("google"):
            return "logo_gemini"
        case _ where lowerProvider.contains("gemini"):
            return "logo_gemini"
        case _ where lowerProvider.contains("claude"):
            return "logo_claude"
        case _ where lowerProvider.contains("gpt"):
            return "logo_chatgpt"
        case _ where lowerProvider.contains("perplexity"):
            return "logo_perplexity"
        case _ where lowerProvider.contains("deepseek"):
            return "logo_deepseek"
        case _ where lowerProvider.contains("mistral"):
            return "logo_mistral"
        case _ where lowerProvider.contains("ollama"):
            return "logo_ollama"
        case _ where lowerProvider.contains("openrouter"):
            return "logo_openrouter"
        case _ where lowerProvider.contains("groq"):
            return "logo_groq"
        case _ where lowerProvider.contains("lmstudio"):
            return "logo_lmstudio"
        case _ where lowerProvider.contains("xai"):
            return "logo_xai"
        default:
            return "sparkles"
        }
    }
}

struct BubbleShape: Shape {
    var myMessage: Bool

    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        
        return Path { path in
            if !myMessage {
                path.move(to: CGPoint(x: 20, y: height))
                path.addLine(to: CGPoint(x: width - 15, y: height))
                path.addCurve(to: CGPoint(x: width, y: height - 15), control1: CGPoint(x: width - 8, y: height), control2: CGPoint(x: width, y: height - 8))
                path.addLine(to: CGPoint(x: width, y: 15))
                path.addCurve(to: CGPoint(x: width - 15, y: 0), control1: CGPoint(x: width, y: 8), control2: CGPoint(x: width - 8, y: 0))
                path.addLine(to: CGPoint(x: 20, y: 0))
                path.addCurve(to: CGPoint(x: 5, y: 15), control1: CGPoint(x: 12, y: 0), control2: CGPoint(x: 5, y: 8))
                path.addLine(to: CGPoint(x: 5, y: height - 10))
                path.addCurve(to: CGPoint(x: 0, y: height), control1: CGPoint(x: 5, y: height - 1), control2: CGPoint(x: 0, y: height))
                path.addLine(to: CGPoint(x: -1, y: height))
                path.addCurve(to: CGPoint(x: 12, y: height - 4), control1: CGPoint(x: 4, y: height + 1), control2: CGPoint(x: 8, y: height - 1))
                path.addCurve(to: CGPoint(x: 20, y: height), control1: CGPoint(x: 15, y: height), control2: CGPoint(x: 20, y: height))
            } else {
                path.move(to: CGPoint(x: width - 20, y: height))
                path.addLine(to: CGPoint(x: 15, y: height))
                path.addCurve(to: CGPoint(x: 0, y: height - 15), control1: CGPoint(x: 8, y: height), control2: CGPoint(x: 0, y: height - 8))
                path.addLine(to: CGPoint(x: 0, y: 15))
                path.addCurve(to: CGPoint(x: 15, y: 0), control1: CGPoint(x: 0, y: 8), control2: CGPoint(x: 8, y: 0))
                path.addLine(to: CGPoint(x: width - 20, y: 0))
                path.addCurve(to: CGPoint(x: width - 5, y: 15), control1: CGPoint(x: width - 12, y: 0), control2: CGPoint(x: width - 5, y: 8))
                path.addLine(to: CGPoint(x: width - 5, y: height - 10))
                path.addCurve(to: CGPoint(x: width, y: height), control1: CGPoint(x: width - 5, y: height - 1), control2: CGPoint(x: width, y: height))
                path.addLine(to: CGPoint(x: width + 1, y: height))
                path.addCurve(to: CGPoint(x: width - 12, y: height - 4), control1: CGPoint(x: width - 4, y: height + 1), control2: CGPoint(x: width - 8, y: height - 1))
                path.addCurve(to: CGPoint(x: width - 20, y: height), control1: CGPoint(x: width - 15, y: height), control2: CGPoint(x: width - 20, y: height))
            }
        }
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
