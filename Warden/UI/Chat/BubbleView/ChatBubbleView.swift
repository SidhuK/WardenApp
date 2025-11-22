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
                    .frame(width: 20, height: 20)
            }
            
            if content.own && !content.systemMessage {
                Spacer(minLength: 40)
            }

            bubbleView
                .modifier(StreamingPulseModifier(isStreaming: content.isStreaming))

            if content.own && !content.systemMessage {
                userAvatar
                    .frame(width: 20, height: 20)
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
    }
    
    private struct BubbleStyle {
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let background: AnyView
        let overlay: AnyView?
        let shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)?
        let secondaryShadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)?
    }
    
    @ViewBuilder
    private func unifiedBubble(role: BubbleRole) -> some View {
        let style = bubbleStyle(for: role)
        
        VStack(alignment: .leading, spacing: 4) {
            bubbleContent(for: role)
        }
        .padding(.horizontal, style.horizontalPadding)
        .padding(.vertical, style.verticalPadding)
        .background(style.background)
        .clipShape(RoundedRectangle(cornerRadius: bubbleCornerRadius))
        .overlay(style.overlay)
        .modifier(BubbleShadowModifier(
            shadow: style.shadow,
            secondaryShadow: style.secondaryShadow
        ))
    }
    
    @ViewBuilder
    private func bubbleContent(for role: BubbleRole) -> some View {
        switch role {
        case .user:
            if content.waitingForResponse ?? false {
                messageBody
            } else {
                messageBody
            }
            
        case .assistant:
            if content.waitingForResponse ?? false {
                thinkingView
            } else {
                messageBody
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
    
    private func bubbleStyle(for role: BubbleRole) -> BubbleStyle {
        switch role {
        case .user:
            return BubbleStyle(
                horizontalPadding: 12,
                verticalPadding: 9,
                background: AnyView(
                    ZStack {
                        LinearGradient(
                            gradient: Gradient(colors: [
                                Color.accentColor.opacity(0.85),
                                Color.accentColor.opacity(0.75)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        
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
                    }
                ),
                overlay: AnyView(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .stroke(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.white.opacity(0.2),
                                    Color.accentColor.opacity(0.15)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 0.5
                        )
                ),
                shadow: (Color.accentColor.opacity(0.15), 2, 0, 1),
                secondaryShadow: (Color.black.opacity(0.05), 4, 0, 2)
            )
            
        case .assistant:
            return BubbleStyle(
                horizontalPadding: 12,
                verticalPadding: 9,
                background: AnyView(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                ),
                overlay: AnyView(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                ),
                shadow: nil,
                secondaryShadow: nil
            )
            
        case .system:
            return BubbleStyle(
                horizontalPadding: 11,
                verticalPadding: 8,
                background: AnyView(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .fill(Color.accentColor.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                                .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.9)
                        )
                ),
                overlay: nil,
                shadow: nil,
                secondaryShadow: nil
            )
            
        case .error:
            return BubbleStyle(
                horizontalPadding: 11,
                verticalPadding: 8,
                background: AnyView(
                    RoundedRectangle(cornerRadius: bubbleCornerRadius)
                        .fill(AppConstants.destructive.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: bubbleCornerRadius)
                                .stroke(AppConstants.destructive.opacity(0.5), lineWidth: 1)
                        )
                ),
                overlay: nil,
                shadow: nil,
                secondaryShadow: nil
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
        .foregroundColor(content.own ? .white : AppConstants.textPrimary)
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
                .font(.system(size: 10, weight: .semibold))
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.accentColor)
                } else {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                        .foregroundColor(.accentColor)
                }
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
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

// MARK: - Bubble Shadow Modifier

struct BubbleShadowModifier: ViewModifier {
    let shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)?
    let secondaryShadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat)?
    
    func body(content: Content) -> some View {
        if let shadow = shadow {
            if let secondaryShadow = secondaryShadow {
                content
                    .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
                    .shadow(color: secondaryShadow.color, radius: secondaryShadow.radius, x: secondaryShadow.x, y: secondaryShadow.y)
            } else {
                content
                    .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
            }
        } else {
            content
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
